package com.tp.analisis;

import com.google.gson.Gson;
import com.google.gson.JsonObject;
import com.tp.modelo.Post;
import com.tp.modelo.PoisonPill;
import com.tp.modelo.PipelineMessage;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.logging.Logger;
import java.util.regex.Pattern;

public class EtapaCategorias {
    private static final Logger logger = Logger.getLogger(EtapaCategorias.class.getName());
    private static final Pattern TOKENIZER = Pattern.compile("[\\s\\p{P}]+");

    private final BlockingQueue<Object> queueAB;
    private final BlockingQueue<Object> queueBC;
    private final int kC;
    private final Map<String, java.util.Set<String>> palabrasPorCategoria;
    private static AtomicBoolean pillPropagated = new AtomicBoolean(false);

    public EtapaCategorias(BlockingQueue<Object> queueAB, BlockingQueue<Object> queueBC, int kC) {
        this.queueAB = queueAB;
        this.queueBC = queueBC;
        this.kC = kC;
        this.palabrasPorCategoria = new HashMap<>();
        cargarListas();
    }

    private void cargarListas() {
        try {
            BufferedReader reader = new BufferedReader(
                    new InputStreamReader(getClass().getResourceAsStream("/palabras_prohibidas.json")));
            StringBuilder sb = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                sb.append(line);
            }
            reader.close();

            Gson gson = new Gson();
            JsonObject obj = gson.fromJson(sb.toString(), JsonObject.class);
            obj.keySet().forEach(categoria -> {
                java.util.Set<String> palabras = new java.util.HashSet<>();
                obj.getAsJsonArray(categoria).forEach(e -> palabras.add(e.getAsString()));
                palabrasPorCategoria.put(categoria, palabras);
            });
        } catch (Exception e) {
            logger.severe("Error cargando palabras_prohibidas.json: " + e.getMessage());
        }
    }

    public void procesarWorker() {
        try {
            while (true) {
                PipelineMessage msg = (PipelineMessage) queueAB.take();

                if (msg instanceof PoisonPill) {
                    logger.info(Thread.currentThread().getName() + " recibió poison pill");
                    propagarPills();
                    break;
                }

                Post post = (Post) msg;
                logger.info(Thread.currentThread().getName() + " procesando post_id=" + post.getPostId());

                List<String> categorias = detectarCategorias(post.getTexto());
                post.setCategorias(categorias);

                queueBC.put(post);
                logger.info(Thread.currentThread().getName() + " terminó post_id=" + post.getPostId());
            }
        } catch (InterruptedException e) {
            logger.warning(Thread.currentThread().getName() + " interrumpido: " + e.getMessage());
        }
    }

    private List<String> detectarCategorias(String texto) {
        List<String> categorias = new ArrayList<>();
        String[] tokens = TOKENIZER.split(texto.toLowerCase());

        for (String categoria : palabrasPorCategoria.keySet()) {
            java.util.Set<String> palabras = palabrasPorCategoria.get(categoria);
            for (String token : tokens) {
                if (palabras.contains(token)) {
                    if (!categorias.contains(categoria)) {
                        categorias.add(categoria);
                    }
                    break;
                }
            }
        }

        return categorias;
    }

    private void propagarPills() {
        if (!pillPropagated.compareAndSet(false, true)) {
            return;
        }

        try {
            for (int i = 0; i < kC; i++) {
                queueBC.put(PoisonPill.INSTANCE);
                logger.info(Thread.currentThread().getName() + " propagó poison pill " + (i + 1) + "/" + kC);
            }
        } catch (InterruptedException e) {
            logger.warning("Error propagando pills: " + e.getMessage());
        }
    }
}
