package com.tp;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.tp.analisis.EtapaCategorias;
import com.tp.analisis.EtapaSentimiento;
import com.tp.analisis.EtapaSpam;
import com.tp.modelo.Resultado;

import java.io.FileWriter;
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
    private static final Logger logger = Logger.getLogger(Main.class.getName());

    private static final int K_A = 3;
    private static final int K_B = 3;
    private static final int K_C = 3;
    private static final int QUEUE_CAPACITY = 50;

    public static void main(String[] args) {
        configureLogging();
        logger.info("=== Iniciando Pipeline de Análisis de Posts ===");

        long tiempoTotalInicio = System.currentTimeMillis();

        // Crear BlockingQueues
        BlockingQueue<Object> queueIn = new LinkedBlockingQueue<>(QUEUE_CAPACITY);
        BlockingQueue<Object> queueAB = new LinkedBlockingQueue<>(QUEUE_CAPACITY);
        BlockingQueue<Object> queueBC = new LinkedBlockingQueue<>(QUEUE_CAPACITY);

        // Crear cola de resultados (lock-free)
        ConcurrentLinkedQueue<Resultado> resultados = new ConcurrentLinkedQueue<>();

        // Crear contadores de tiempo por etapa
        LongAdder tiempoEtapaA = new LongAdder();
        LongAdder tiempoEtapaB = new LongAdder();
        LongAdder tiempoEtapaC = new LongAdder();

        // Crear ExecutorServices
        ExecutorService executorA = Executors.newFixedThreadPool(K_A);
        ExecutorService executorB = Executors.newFixedThreadPool(K_B);
        ExecutorService executorC = Executors.newFixedThreadPool(K_C);

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

        try {
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

            long tiempoTotalFin = System.currentTimeMillis();
            long tiempoTotalMs = tiempoTotalFin - tiempoTotalInicio;

            // Volcar resultados a JSON
            List<Resultado> listaResultados = new ArrayList<>(resultados);
            guardarResultados(listaResultados);

            // Imprimir métricas
            imprimirMetricas(listaResultados, tiempoTotalMs, tiempoEtapaA, tiempoEtapaB, tiempoEtapaC);

        } catch (InterruptedException e) {
            logger.severe("Error esperando shutdown: " + e.getMessage());
            Thread.currentThread().interrupt();
        }

        logger.info("=== Pipeline completado ===");
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

        long aprobados = resultados.stream()
                .filter(r -> "APROBADO".equals(r.getDecision()))
                .count();
        long rechazados = resultados.size() - aprobados;
        System.out.println("\nDecisiones:");
        System.out.println("  APROBADOS: " + aprobados);
        System.out.println("  RECHAZADOS: " + rechazados);
    }

    private static void configureLogging() {
        System.setProperty("java.util.logging.SimpleFormatter.format",
                "[%1$tT.%1$tL] [%4$s] [%2$s] %5$s%n");
    }
}
