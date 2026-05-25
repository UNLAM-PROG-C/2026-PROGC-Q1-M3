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
import java.util.logging.Logger;

public class Main {

    static {
        System.setProperty("java.util.logging.SimpleFormatter.format",
                "[%1$tT.%1$tL] [%4$s] [%2$s] %5$s%n");
    }

    private static final Logger LOG = Logger.getLogger(Main.class.getName());

    private static final int K_A = 3;
    private static final int K_B = 3;
    private static final int K_C = 3;

    // Capacidad limitada → induce backpressure. Si un pool downstream se atrasa,
    // los workers upstream se bloquean en put() y dejan de fabricar trabajo.
    private static final int CAPACIDAD_COLA = 50;

    public static void main(String[] args) throws Exception {
        LOG.info("Iniciando pipeline con K_A=" + K_A + ", K_B=" + K_B + ", K_C=" + K_C);

        BlockingQueue<PipelineMessage> colaEntrada = new LinkedBlockingQueue<>(CAPACIDAD_COLA);
        BlockingQueue<PipelineMessage> colaAB = new LinkedBlockingQueue<>(CAPACIDAD_COLA);
        BlockingQueue<PipelineMessage> colaBC = new LinkedBlockingQueue<>(CAPACIDAD_COLA);
        ConcurrentLinkedQueue<Resultado> resultados = new ConcurrentLinkedQueue<>();

        LongAdder tiempoEtapaA = new LongAdder();
        LongAdder tiempoEtapaB = new LongAdder();
        LongAdder tiempoEtapaC = new LongAdder();

        ExecutorService poolA = Executors.newFixedThreadPool(K_A, named("EtapaA"));
        ExecutorService poolB = Executors.newFixedThreadPool(K_B, named("EtapaB"));
        ExecutorService poolC = Executors.newFixedThreadPool(K_C, named("EtapaC"));

        EtapaSentimiento etapaA = new EtapaSentimiento(colaEntrada, colaAB, K_A, K_B, tiempoEtapaA);
        EtapaCategorias  etapaB = new EtapaCategorias(colaAB, colaBC, K_B, K_C, tiempoEtapaB);
        EtapaSpam        etapaC = new EtapaSpam(colaBC, resultados, K_C, tiempoEtapaC);

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

    private static java.util.concurrent.ThreadFactory named(String prefijo) {
        java.util.concurrent.atomic.AtomicInteger n = new java.util.concurrent.atomic.AtomicInteger(0);
        return r -> {
            Thread t = new Thread(r, prefijo + "-W" + n.incrementAndGet());
            t.setDaemon(false);
            return t;
        };
    }
}
