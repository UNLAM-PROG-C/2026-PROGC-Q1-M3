package com.tp.analisis;

import com.tp.modelo.PipelineMessage;
import com.tp.modelo.PoisonPill;
import com.tp.modelo.Post;
import com.tp.modelo.PostMessage;
import com.tp.modelo.Resultado;

import java.util.concurrent.BlockingQueue;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.LongAdder;
import java.util.logging.Level;
import java.util.logging.Logger;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class EtapaSpam {

    private static final Logger LOG = Logger.getLogger(EtapaSpam.class.getName());

    private static final Pattern SPAM_KEYWORDS =
            Pattern.compile("(?i)(gratis|comprar ya|click aqui|\\$\\$+|!!!|https?://)");

    private static final double PESO_KEYWORDS = 0.4;
    private static final double PESO_MAYUSCULAS = 0.3;
    private static final double PESO_LONGITUD = 0.3;

    private final BlockingQueue<PipelineMessage> entrada;
    private final ConcurrentLinkedQueue<Resultado> resultados;
    private final int workers;
    private final LongAdder tiempoAcumNanos;
    private final AtomicInteger restantes;

    public EtapaSpam(BlockingQueue<PipelineMessage> entrada,
                     ConcurrentLinkedQueue<Resultado> resultados,
                     int workers,
                     LongAdder tiempoAcumNanos) {
        this.entrada = entrada;
        this.resultados = resultados;
        this.workers = workers;
        this.tiempoAcumNanos = tiempoAcumNanos;
        this.restantes = new AtomicInteger(workers);
    }

    public void lanzar(ExecutorService pool) {
        for (int i = 0; i < workers; i++) {
            pool.submit(this::loop);
        }
    }

    private void loop() {
        try {
            while (true) {
                PipelineMessage msg = entrada.take();
                if (msg instanceof PoisonPill) {
                    restantes.decrementAndGet();
                    return;
                }
                Post post = ((PostMessage) msg).post();
                long inicio = System.nanoTime();

                double spamScore = calcularSpamScore(post.getTexto());
                String decision = decidir(post, spamScore);
                long tiempoMs = (System.nanoTime() - post.getTimestampEntradaNanos()) / 1_000_000L;

                Resultado r = new Resultado(
                        post.getPostId(),
                        post.getTexto(),
                        redondear(spamScore),
                        post.getSentimiento(),
                        post.getCategorias(),
                        decision,
                        tiempoMs
                );
                // ConcurrentLinkedQueue es lock-free: evita el cuello de botella de un Lock o
                // List sincronizada cuando todos los workers de C escriben a la vez.
                resultados.add(r);

                tiempoAcumNanos.add(System.nanoTime() - inicio);
                LOG.info("Post " + post.getPostId() + " → spamScore=" + redondear(spamScore)
                        + ", decision=" + decision + " (" + tiempoMs + "ms total)");
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            LOG.log(Level.WARNING, "Worker spam interrumpido", e);
        } catch (Exception e) {
            LOG.log(Level.SEVERE, "Error en worker spam", e);
        }
    }

    private double calcularSpamScore(String texto) {
        if (texto == null) return 0.0;

        double score = 0.0;

        Matcher m = SPAM_KEYWORDS.matcher(texto);
        if (m.find()) {
            score += PESO_KEYWORDS;
        }

        int letras = 0, mayus = 0;
        for (int i = 0; i < texto.length(); i++) {
            char c = texto.charAt(i);
            if (Character.isLetter(c)) {
                letras++;
                if (Character.isUpperCase(c)) mayus++;
            }
        }
        if (letras > 0 && ((double) mayus / letras) > 0.7) {
            score += PESO_MAYUSCULAS;
        }

        int len = texto.length();
        if (len < 5 || len > 280) {
            score += PESO_LONGITUD;
        }

        if (score < 0.0) score = 0.0;
        if (score > 1.0) score = 1.0;
        return score;
    }

    private String decidir(Post post, double spamScore) {
        boolean tieneCategorias = post.getCategorias() != null && !post.getCategorias().isEmpty();
        boolean spamAlto = spamScore > 0.7;
        boolean odioNegativo = "negativo".equals(post.getSentimiento())
                && post.getCategorias() != null
                && post.getCategorias().contains("odio");
        if (tieneCategorias || spamAlto || odioNegativo) {
            return "RECHAZADO";
        }
        return "APROBADO";
    }

    private double redondear(double v) {
        return Math.round(v * 100.0) / 100.0;
    }
}
