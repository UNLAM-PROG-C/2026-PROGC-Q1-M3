package com.tp.analisis;

import com.tp.modelo.Post;
import com.tp.modelo.PoisonPill;
import com.tp.modelo.PipelineMessage;
import com.tp.modelo.Resultado;

import java.util.concurrent.BlockingQueue;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.atomic.LongAdder;
import java.util.logging.Logger;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class EtapaSpam {
    private static final Logger logger = Logger.getLogger(EtapaSpam.class.getName());
    private static final Pattern SPAM_PATTERN =
            Pattern.compile("(?i)(gratis|comprar ya|click aqui|\\$\\$+|!!!|https?://)");

    private final BlockingQueue<Object> queueBC;
    private final ConcurrentLinkedQueue<Resultado> resultados;
    private final LongAdder tiempoEtapaC;

    public EtapaSpam(BlockingQueue<Object> queueBC, ConcurrentLinkedQueue<Resultado> resultados,
                     LongAdder tiempoEtapaC) {
        this.queueBC = queueBC;
        this.resultados = resultados;
        this.tiempoEtapaC = tiempoEtapaC;
    }

    public void procesarWorker() {
        try {
            while (true) {
                PipelineMessage msg = (PipelineMessage) queueBC.take();

                if (msg instanceof PoisonPill) {
                    logger.info(Thread.currentThread().getName() + " recibió poison pill");
                    break;
                }

                Post post = (Post) msg;
                logger.info(Thread.currentThread().getName() + " procesando post_id=" + post.getPostId());

                long tiempoInicio = System.nanoTime();

                double spamScore = calcularSpamScore(post.getTexto());
                post.setSpamScore(spamScore);

                String decision = tomarDecision(post);
                post.setDecision(decision);

                long tiempoMs = (System.nanoTime() - post.getTimestampInicio()) / 1_000_000;
                long tiempoEtapaMs = (System.nanoTime() - tiempoInicio) / 1_000_000;

                Resultado resultado = new Resultado(
                        post.getPostId(),
                        post.getTexto(),
                        spamScore,
                        post.getSentimiento(),
                        post.getCategorias(),
                        decision,
                        tiempoMs
                );

                resultados.add(resultado);
                tiempoEtapaC.add(tiempoEtapaMs);

                logger.info(Thread.currentThread().getName() + " terminó post_id=" + post.getPostId());
            }
        } catch (InterruptedException e) {
            logger.warning(Thread.currentThread().getName() + " interrumpido: " + e.getMessage());
        }
    }

    private double calcularSpamScore(String texto) {
        double score = 0.0;

        // Peso 0.4: Keywords spam
        Matcher matcher = SPAM_PATTERN.matcher(texto);
        int matchCount = 0;
        while (matcher.find()) {
            matchCount++;
        }
        if (matchCount > 0) {
            score += Math.min(0.4, matchCount * 0.1);
        }

        // Peso 0.3: Ratio mayúsculas
        int mayusculas = 0;
        int letras = 0;
        for (char c : texto.toCharArray()) {
            if (Character.isLetter(c)) {
                letras++;
                if (Character.isUpperCase(c)) {
                    mayusculas++;
                }
            }
        }
        if (letras > 0 && (double) mayusculas / letras > 0.7) {
            score += 0.3;
        }

        // Peso 0.3: Longitud anómala
        if (texto.length() < 5 || texto.length() > 280) {
            score += 0.3;
        }

        return Math.min(1.0, score);
    }

    private String tomarDecision(Post post) {
        boolean tieneCategoriasProhibidas = !post.getCategorias().isEmpty();
        boolean esSpam = post.getSpamScore() > 0.7;
        boolean esNegativoOdiador = "negativo".equals(post.getSentimiento()) &&
                post.getCategorias().contains("odio");

        if (tieneCategoriasProhibidas || esSpam || esNegativoOdiador) {
            return "RECHAZADO";
        }
        return "APROBADO";
    }
}
