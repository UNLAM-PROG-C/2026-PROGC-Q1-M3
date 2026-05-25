package com.tp;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.tp.analisis.EtapaCategorias;
import com.tp.analisis.EtapaSentimiento;
import com.tp.analisis.EtapaSpam;
import com.tp.modelo.PipelineMessage;
import com.tp.modelo.Resultado;

import java.io.FileWriter;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.LongAdder;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryUsage;
import java.lang.management.ThreadMXBean;
import java.util.logging.Logger;

public class Main {

    static {
        System.setProperty("java.util.logging.SimpleFormatter.format",
                "[%1$tT.%1$tL] [%4$s] [%2$s] %5$s%n");
    }

    private static final Logger LOG = Logger.getLogger(Main.class.getName());

    private static final int K_A = 10;
    private static final int K_B = 10;
    private static final int K_C = 10;

    // Capacidad limitada → induce backpressure. Si un pool downstream se atrasa,
    // los workers upstream se bloquean en put() y dejan de fabricar trabajo.
    private static final int CAPACIDAD_COLA = 50;

    public static void main(String[] args) throws Exception {
        ThreadMXBean tmx = ManagementFactory.getThreadMXBean();
        if (tmx.isThreadCpuTimeSupported()) tmx.setThreadCpuTimeEnabled(true);

        // Acumuladores de CPU time por pool. Cada worker los escribe al terminar (ver namedCpu).
        LongAdder cpuNanosA = new LongAdder();
        LongAdder cpuNanosB = new LongAdder();
        LongAdder cpuNanosC = new LongAdder();

        LOG.info("Iniciando pipeline con K_A=" + K_A + ", K_B=" + K_B + ", K_C=" + K_C);

        BlockingQueue<PipelineMessage> colaEntrada = new LinkedBlockingQueue<>(CAPACIDAD_COLA);
        BlockingQueue<PipelineMessage> colaAB = new LinkedBlockingQueue<>(CAPACIDAD_COLA);
        BlockingQueue<PipelineMessage> colaBC = new LinkedBlockingQueue<>(CAPACIDAD_COLA);
        ConcurrentLinkedQueue<Resultado> resultados = new ConcurrentLinkedQueue<>();

        LongAdder tiempoEtapaA = new LongAdder();
        LongAdder tiempoEtapaB = new LongAdder();
        LongAdder tiempoEtapaC = new LongAdder();

        ExecutorService poolA = Executors.newFixedThreadPool(K_A, namedCpu("EtapaA", tmx, cpuNanosA));
        ExecutorService poolB = Executors.newFixedThreadPool(K_B, namedCpu("EtapaB", tmx, cpuNanosB));
        ExecutorService poolC = Executors.newFixedThreadPool(K_C, namedCpu("EtapaC", tmx, cpuNanosC));

        EtapaSentimiento etapaA = new EtapaSentimiento(colaEntrada, colaAB, K_A, K_B, tiempoEtapaA);
        EtapaCategorias  etapaB = new EtapaCategorias(colaAB, colaBC, K_B, K_C, tiempoEtapaB);
        EtapaSpam        etapaC = new EtapaSpam(colaBC, resultados, K_C, tiempoEtapaC);

        long heapAntesBytes = ManagementFactory.getMemoryMXBean().getHeapMemoryUsage().getUsed();
        tmx.resetPeakThreadCount();
        long threadsBaseline = tmx.getTotalStartedThreadCount();

        long t0 = System.nanoTime();

        etapaA.lanzar(poolA);
        etapaB.lanzar(poolB);
        etapaC.lanzar(poolC);

        Thread productorThread = new Thread(new Productor(colaEntrada, K_A), "Productor");
        productorThread.start();
        productorThread.join();

        // Shutdown ordenado: cada pool recibe pills via la propagacion entre etapas (ver
        // EtapaSentimiento/EtapaCategorias). Aca solo esperamos que cada pool termine.
        poolA.shutdown();
        poolA.awaitTermination(10, TimeUnit.MINUTES);

        poolB.shutdown();
        poolB.awaitTermination(10, TimeUnit.MINUTES);

        poolC.shutdown();
        poolC.awaitTermination(10, TimeUnit.MINUTES);

        long elapsedNanos = System.nanoTime() - t0;

        volcarResultados(resultados);
        imprimirMetricas(resultados, elapsedNanos, tiempoEtapaA, tiempoEtapaB, tiempoEtapaC);
        imprimirMetricasSistema(tmx, heapAntesBytes, threadsBaseline, cpuNanosA, cpuNanosB, cpuNanosC);
    }

    private static void volcarResultados(ConcurrentLinkedQueue<Resultado> resultados) throws Exception {
        List<Resultado> lista = new ArrayList<>(resultados);
        Gson gson = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
        Path out = Paths.get("resultados.json");
        try (FileWriter fw = new FileWriter(out.toFile(), java.nio.charset.StandardCharsets.UTF_8)) {
            gson.toJson(lista, fw);
        }
        LOG.info("Volcados " + lista.size() + " resultados a " + out.toAbsolutePath());
    }

    private static void imprimirMetricas(ConcurrentLinkedQueue<Resultado> resultados,
                                         long elapsedNanos,
                                         LongAdder a, LongAdder b, LongAdder c) {
        int total = resultados.size();
        double elapsedSec = elapsedNanos / 1_000_000_000.0;
        double throughput = total / elapsedSec;
        double promedioMs = resultados.stream().mapToLong(Resultado::getTiempoProcesamientoMs).average().orElse(0.0);

        double promedioA = total == 0 ? 0.0 : (a.sum() / 1_000_000.0) / total;
        double promedioB = total == 0 ? 0.0 : (b.sum() / 1_000_000.0) / total;
        double promedioC = total == 0 ? 0.0 : (c.sum() / 1_000_000.0) / total;

        System.out.println();
        System.out.println("=====================  METRICAS  =====================");
        System.out.printf ("Posts procesados              : %d%n", total);
        System.out.printf ("Tiempo total pipeline         : %.3f s%n", elapsedSec);
        System.out.printf ("Throughput                    : %.2f posts/s%n", throughput);
        System.out.printf ("Tiempo promedio por post      : %.2f ms (entrada→fin)%n", promedioMs);
        System.out.printf ("Tiempo promedio etapa A       : %.3f ms%n", promedioA);
        System.out.printf ("Tiempo promedio etapa B       : %.3f ms%n", promedioB);
        System.out.printf ("Tiempo promedio etapa C       : %.3f ms%n", promedioC);
        System.out.println("======================================================");
    }

    // Reemplaza a named(): además de dar nombre al thread, captura el CPU time
    // de cada worker justo antes de que el thread muera (momento más confiable para leerlo).
    private static java.util.concurrent.ThreadFactory namedCpu(String prefijo,
                                                                ThreadMXBean tmx,
                                                                LongAdder cpuAccum) {
        java.util.concurrent.atomic.AtomicInteger n = new java.util.concurrent.atomic.AtomicInteger(0);
        return r -> {
            Thread t = new Thread(() -> {
                r.run();
                if (tmx.isCurrentThreadCpuTimeSupported()) {
                    long cpu = tmx.getCurrentThreadCpuTime();
                    if (cpu > 0) cpuAccum.add(cpu);
                }
            }, prefijo + "-W" + n.incrementAndGet());
            t.setDaemon(false);
            return t;
        };
    }

    private static void imprimirMetricasSistema(ThreadMXBean tmx,
                                                long heapAntesBytes,
                                                long threadsBaseline,
                                                LongAdder cpuNanosA,
                                                LongAdder cpuNanosB,
                                                LongAdder cpuNanosC) {
        MemoryUsage heap    = ManagementFactory.getMemoryMXBean().getHeapMemoryUsage();
        MemoryUsage nonHeap = ManagementFactory.getMemoryMXBean().getNonHeapMemoryUsage();

        long threadsApp   = tmx.getTotalStartedThreadCount() - threadsBaseline;
        long threadsJvm   = threadsBaseline; // threads de la JVM activos antes del pipeline
        int  peakTotal    = tmx.getPeakThreadCount();

        System.out.println();
        System.out.println("==========  METRICAS DE RENDIMIENTO Y SISTEMA  ==========");
        System.out.println("--- Threads ---");
        System.out.printf("Threads internos JVM (base)             : %d%n",   threadsJvm);
        System.out.printf("Threads creados por la aplicacion       : %d%n",   threadsApp);
        System.out.printf("  Productor                             : 1%n");
        System.out.printf("  Pool A - Sentimiento                  : %d%n",   K_A);
        System.out.printf("  Pool B - Categorias                   : %d%n",   K_B);
        System.out.printf("  Pool C - Spam/Decision                : %d%n",   K_C);
        System.out.printf("Peak total (app + JVM) durante pipeline : %d%n",   peakTotal);
        System.out.printf("Threads activos al finalizar (solo JVM) : %d%n",   tmx.getThreadCount());
        System.out.println("--- Memoria ---");
        System.out.printf("Heap antes del pipeline                 : %.2f MB%n", heapAntesBytes / 1_048_576.0);
        System.out.printf("Heap al finalizar (usado)               : %.2f MB%n", heap.getUsed()       / 1_048_576.0);
        System.out.printf("Heap comprometido (committed)           : %.2f MB%n", heap.getCommitted()  / 1_048_576.0);
        System.out.printf("Non-heap (metaspace + JIT cache)        : %.2f MB%n", nonHeap.getUsed()    / 1_048_576.0);
        System.out.println("--- CPU (solo threads de la aplicacion) ---");
        if (tmx.isThreadCpuTimeSupported()) {
            System.out.printf("CPU time Pool A - Sentimiento (%d th)    : %.3f ms%n", K_A, cpuNanosA.sum() / 1_000_000.0);
            System.out.printf("CPU time Pool B - Categorias  (%d th)    : %.3f ms%n", K_B, cpuNanosB.sum() / 1_000_000.0);
            System.out.printf("CPU time Pool C - Spam/Dec.   (%d th)    : %.3f ms%n", K_C, cpuNanosC.sum() / 1_000_000.0);
            System.out.printf("CPU time total aplicacion               : %.3f ms%n",
                    (cpuNanosA.sum() + cpuNanosB.sum() + cpuNanosC.sum()) / 1_000_000.0);
        } else {
            System.out.println("CPU time por pool: no soportado en esta JVM");
        }
        System.out.println("==========================================================");
    }
}
