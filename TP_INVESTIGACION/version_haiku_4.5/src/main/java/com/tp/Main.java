package com.tp;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.tp.analisis.EtapaCategorias;
import com.tp.analisis.EtapaSentimiento;
import com.tp.analisis.EtapaSpam;
import com.tp.modelo.Resultado;

import java.io.FileWriter;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryUsage;
import java.lang.management.ThreadMXBean;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.LongAdder;
import java.util.logging.Logger;

public class Main {

    static {
        System.setProperty("java.util.logging.SimpleFormatter.format",
                "[%1$tT.%1$tL] [%4$s] [%2$s] %5$s%n");
    }

    private static final Logger logger = Logger.getLogger(Main.class.getName());

    private static final int K_A = 10;
    private static final int K_B = 10;
    private static final int K_C = 10;
    private static final int QUEUE_CAPACITY = 50;

    public static void main(String[] args) throws InterruptedException {
        // --- Metrica 2: Rendimiento — inicializar ThreadMXBean para CPU time por pool ---
        ThreadMXBean tmx = ManagementFactory.getThreadMXBean();
        if (tmx.isThreadCpuTimeSupported()) {
            tmx.setThreadCpuTimeEnabled(true);
        }

        // Acumuladores de CPU time por pool (cada worker los escribe al terminar)
        LongAdder cpuNanosA = new LongAdder();
        LongAdder cpuNanosB = new LongAdder();
        LongAdder cpuNanosC = new LongAdder();

        logger.info("=== Iniciando Pipeline de Análisis de Posts ===");

        long tiempoTotalInicio = System.currentTimeMillis();

        // Crear BlockingQueues
        BlockingQueue<Object> queueIn = new LinkedBlockingQueue<>(QUEUE_CAPACITY);
        BlockingQueue<Object> queueAB = new LinkedBlockingQueue<>(QUEUE_CAPACITY);
        BlockingQueue<Object> queueBC = new LinkedBlockingQueue<>(QUEUE_CAPACITY);

        // Crear cola de resultados (lock-free)
        ConcurrentLinkedQueue<Resultado> resultados = new ConcurrentLinkedQueue<>();

        // Crear contadores de tiempo por etapa (wall-clock acumulado por worker)
        LongAdder tiempoEtapaA = new LongAdder();
        LongAdder tiempoEtapaB = new LongAdder();
        LongAdder tiempoEtapaC = new LongAdder();

        // Crear ExecutorServices con factories que capturan CPU time al terminar cada thread
        ExecutorService executorA = Executors.newFixedThreadPool(K_A, namedCpu("EtapaA", tmx, cpuNanosA));
        ExecutorService executorB = Executors.newFixedThreadPool(K_B, namedCpu("EtapaB", tmx, cpuNanosB));
        ExecutorService executorC = Executors.newFixedThreadPool(K_C, namedCpu("EtapaC", tmx, cpuNanosC));

        // --- Snapshot de memoria ANTES del pipeline ---
        long heapAntesBytes = ManagementFactory.getMemoryMXBean().getHeapMemoryUsage().getUsed();
        tmx.resetPeakThreadCount();
        long threadsBaseline = tmx.getTotalStartedThreadCount();

        // Etapa 0: Productor (en un thread separado)
        ExecutorService executorProductor = Executors.newSingleThreadExecutor();
        Productor productor = new Productor(queueIn, K_A);
        executorProductor.submit(productor);

        // Etapa A: Sentimiento
        EtapaSentimiento etapaSentimiento = new EtapaSentimiento(queueIn, queueAB, K_B);
        for (int i = 0; i < K_A; i++) {
            executorA.submit(() -> {
                long tiempoInicio = System.nanoTime();
                etapaSentimiento.procesarWorker();
                long tiempoMs = (System.nanoTime() - tiempoInicio) / 1_000_000;
                tiempoEtapaA.add(tiempoMs);
            });
        }

        // Etapa B: Categorías
        EtapaCategorias etapaCategorias = new EtapaCategorias(queueAB, queueBC, K_C);
        for (int i = 0; i < K_B; i++) {
            executorB.submit(() -> {
                long tiempoInicio = System.nanoTime();
                etapaCategorias.procesarWorker();
                long tiempoMs = (System.nanoTime() - tiempoInicio) / 1_000_000;
                tiempoEtapaB.add(tiempoMs);
            });
        }

        // Etapa C: Spam y decisión
        EtapaSpam etapaSpam = new EtapaSpam(queueBC, resultados, tiempoEtapaC);
        for (int i = 0; i < K_C; i++) {
            executorC.submit(etapaSpam::procesarWorker);
        }

        // Shutdown Productor
        executorProductor.shutdown();
        if (!executorProductor.awaitTermination(60, TimeUnit.SECONDS)) {
            logger.warning("Productor timeout");
        }
        logger.info("Productor finalizado");

        // Shutdown Etapa A
        executorA.shutdown();
        if (!executorA.awaitTermination(60, TimeUnit.SECONDS)) {
            logger.warning("Etapa A timeout");
        }
        logger.info("Etapa A finalizada");

        // Shutdown Etapa B
        executorB.shutdown();
        if (!executorB.awaitTermination(60, TimeUnit.SECONDS)) {
            logger.warning("Etapa B timeout");
        }
        logger.info("Etapa B finalizada");

        // Shutdown Etapa C
        executorC.shutdown();
        if (!executorC.awaitTermination(60, TimeUnit.SECONDS)) {
            logger.warning("Etapa C timeout");
        }
        logger.info("Etapa C finalizada");

        long tiempoTotalMs = System.currentTimeMillis() - tiempoTotalInicio;

        // Volcar resultados a JSON
        List<Resultado> listaResultados = new ArrayList<>(resultados);
        guardarResultados(listaResultados);

        // Imprimir métricas de pipeline
        imprimirMetricas(listaResultados, tiempoTotalMs, tiempoEtapaA, tiempoEtapaB, tiempoEtapaC);

        // Imprimir métricas de rendimiento del sistema (Metrica 2)
        imprimirMetricasSistema(tmx, heapAntesBytes, threadsBaseline, cpuNanosA, cpuNanosB, cpuNanosC);

        logger.info("=== Pipeline completado ===");
    }

    /**
     * ThreadFactory que nombra los workers y captura su CPU time (via ThreadMXBean)
     * justo antes de que el thread muera — momento mas confiable para la lectura.
     */
    private static ThreadFactory namedCpu(String prefijo, ThreadMXBean tmx, LongAdder cpuAccum) {
        AtomicInteger n = new AtomicInteger(0);
        return r -> {
            Thread t = new Thread(() -> {
                r.run();
                if (tmx.isCurrentThreadCpuTimeSupported()) {
                    long cpu = tmx.getCurrentThreadCpuTime();
                    if (cpu > 0) {
                        cpuAccum.add(cpu);
                    }
                }
            }, prefijo + "-W" + n.incrementAndGet());
            t.setDaemon(false);
            return t;
        };
    }

    private static void guardarResultados(List<Resultado> listaResultados) {
        try {
            Gson gson = new GsonBuilder().setPrettyPrinting().create();
            FileWriter writer = new FileWriter("resultados.json");
            gson.toJson(listaResultados, writer);
            writer.close();
            logger.info("Resultados guardados en resultados.json");
        } catch (Exception e) {
            logger.severe("Error guardando resultados: " + e.getMessage());
        }
    }

    private static void imprimirMetricas(List<Resultado> resultados, long tiempoTotalMs,
                                         LongAdder tiempoEtapaA, LongAdder tiempoEtapaB,
                                         LongAdder tiempoEtapaC) {
        int totalPosts = resultados.size();

        System.out.println("\n=== MÉTRICAS DEL PIPELINE ===");
        System.out.println("Tiempo total: " + tiempoTotalMs + " ms");
        System.out.println("Posts procesados: " + totalPosts);

        if (tiempoTotalMs > 0) {
            double throughput = (double) totalPosts * 1000 / tiempoTotalMs;
            System.out.printf("Throughput: %.2f posts/segundo%n", throughput);
        }

        if (totalPosts > 0) {
            double tiempoPromedioPorPost = resultados.stream()
                    .mapToLong(Resultado::getTiempoProcesamientoMs)
                    .average()
                    .orElse(0);
            System.out.printf("Tiempo promedio por post: %.2f ms%n", tiempoPromedioPorPost);
        }

        System.out.println("\nTiempo acumulado por etapa:");
        System.out.println("  Etapa A (Sentimiento): " + tiempoEtapaA.sum() + " ms");
        System.out.println("  Etapa B (Categorías):  " + tiempoEtapaB.sum() + " ms");
        System.out.println("  Etapa C (Spam):        " + tiempoEtapaC.sum() + " ms");

        if (totalPosts > 0) {
            System.out.println("\nTiempo promedio por etapa:");
            System.out.printf("  Etapa A: %.2f ms/post%n", (double) tiempoEtapaA.sum() / totalPosts);
            System.out.printf("  Etapa B: %.2f ms/post%n", (double) tiempoEtapaB.sum() / totalPosts);
            System.out.printf("  Etapa C: %.2f ms/post%n", (double) tiempoEtapaC.sum() / totalPosts);
        }

        long aprobados  = resultados.stream().filter(r -> "APROBADO".equals(r.getDecision())).count();
        long rechazados = resultados.size() - aprobados;
        System.out.println("\nDecisiones:");
        System.out.println("  APROBADOS:  " + aprobados);
        System.out.println("  RECHAZADOS: " + rechazados);
    }

    // --- Metrica 2: Rendimiento — memoria y CPU time por pool ---
    private static void imprimirMetricasSistema(ThreadMXBean tmx,
                                                long heapAntesBytes,
                                                long threadsBaseline,
                                                LongAdder cpuNanosA,
                                                LongAdder cpuNanosB,
                                                LongAdder cpuNanosC) {
        MemoryUsage heap    = ManagementFactory.getMemoryMXBean().getHeapMemoryUsage();
        MemoryUsage nonHeap = ManagementFactory.getMemoryMXBean().getNonHeapMemoryUsage();

        long threadsApp = tmx.getTotalStartedThreadCount() - threadsBaseline;
        int  peakTotal  = tmx.getPeakThreadCount();

        System.out.println();
        System.out.println("==========  MÉTRICAS DE RENDIMIENTO Y SISTEMA  ==========");
        System.out.println("--- Threads ---");
        System.out.printf("Threads internos JVM (base)             : %d%n", threadsBaseline);
        System.out.printf("Threads creados por la aplicacion       : %d%n", threadsApp);
        System.out.printf("  Productor                             : 1%n");
        System.out.printf("  Pool A - Sentimiento                  : %d%n", K_A);
        System.out.printf("  Pool B - Categorias                   : %d%n", K_B);
        System.out.printf("  Pool C - Spam/Decision                : %d%n", K_C);
        System.out.printf("Peak total (app + JVM) durante pipeline : %d%n", peakTotal);
        System.out.printf("Threads activos al finalizar (solo JVM) : %d%n", tmx.getThreadCount());
        System.out.println("--- Memoria ---");
        System.out.printf("Heap antes del pipeline                 : %.2f MB%n", heapAntesBytes / 1_048_576.0);
        System.out.printf("Heap al finalizar (usado)               : %.2f MB%n", heap.getUsed()      / 1_048_576.0);
        System.out.printf("Heap comprometido (committed)           : %.2f MB%n", heap.getCommitted() / 1_048_576.0);
        System.out.printf("Non-heap (metaspace + JIT cache)        : %.2f MB%n", nonHeap.getUsed()   / 1_048_576.0);
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
