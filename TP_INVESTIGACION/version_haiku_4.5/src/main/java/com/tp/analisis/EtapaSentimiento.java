package com.tp.analisis;

import com.google.gson.Gson;
import com.google.gson.JsonObject;
import com.tp.modelo.Post;
import com.tp.modelo.PoisonPill;
import com.tp.modelo.PipelineMessage;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.logging.Logger;
import java.util.regex.Pattern;

public class EtapaSentimiento {
    private static final Logger logger = Logger.getLogger(EtapaSentimiento.class.getName());
    private static final Pattern TOKENIZER = Pattern.compile("[\\s\\p{P}]+");

    private final BlockingQueue<Object> queueIn;
    private final BlockingQueue<Object> queueAB;
    private final int kB;
    private final Set<String> palabrasPositivas;
    private final Set<String> palabrasNegativas;
    private static AtomicBoolean pillPropagated = new AtomicBoolean(false);

    public EtapaSentimiento(BlockingQueue<Object> queueIn, BlockingQueue<Object> queueAB, int kB) {
        this.queueIn = queueIn;
        this.queueAB = queueAB;
        this.kB = kB;
        this.palabrasPositivas = new HashSet<>();
        this.palabrasNegativas = new HashSet<>();
        cargarListas();
    }

    private void cargarListas() {
        try {
            BufferedReader reader = new BufferedReader(
                    new InputStreamReader(getClass().getResourceAsStream("/palabras_sentimiento.json")));
            StringBuilder sb = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                sb.append(line);
            }
            reader.close();

            Gson gson = new Gson();
            JsonObject obj = gson.fromJson(sb.toString(), JsonObject.class);
            obj.getAsJsonArray("positivas").forEach(e -> palabrasPositivas.add(e.getAsString()));
            obj.getAsJsonArray("negativas").forEach(e -> palabrasNegativas.add(e.getAsString()));
        } catch (Exception e) {
            logger.severe("Error cargando palabras_sentimiento.json: " + e.getMessage());
        }
    }

    public void procesarWorker() {
        try {
            while (true) {
                PipelineMessage msg = (PipelineMessage) queueIn.take();

                if (msg instanceof PoisonPill) {
                    logger.info(Thread.currentThread().getName() + " recibió poison pill");
                    propagarPills();
                    break;
                }

                Post post = (Post) msg;
                logger.info(Thread.currentThread().getName() + " procesando post_id=" + post.getPostId());

                String sentimiento = analizarSentimiento(post.getTexto());
                post.setSentimiento(sentimiento);

                queueAB.put(post);
                logger.info(Thread.currentThread().getName() + " terminó post_id=" + post.getPostId());
            }
        } catch (InterruptedException e) {
            logger.warning(Thread.currentThread().getName() + " interrumpido: " + e.getMessage());
        }
    }

    private String analizarSentimiento(String texto) {
        String[] tokens = TOKENIZER.split(texto.toLowerCase());
        int hitsPos = 0, hitsNeg = 0;

        for (String token : tokens) {
            if (palabrasPositivas.contains(token)) hitsPos++;
            if (palabrasNegativas.contains(token)) hitsNeg++;
        }

        if (hitsPos > hitsNeg) return "positivo";
        if (hitsPos < hitsNeg) return "negativo";
        return "neutro";
    }

    private void propagarPills() {
        if (!pillPropagated.compareAndSet(false, true)) {
            return;
        }

        try {
            for (int i = 0; i < kB; i++) {
                queueAB.put(PoisonPill.INSTANCE);
                logger.info(Thread.currentThread().getName() + " propagó poison pill " + (i + 1) + "/" + kB);
            }
        } catch (InterruptedException e) {
            logger.warning("Error propagando pills: " + e.getMessage());
        }
    }
}
