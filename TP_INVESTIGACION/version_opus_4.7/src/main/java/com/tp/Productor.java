package com.tp;

import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;
import com.tp.modelo.PipelineMessage;
import com.tp.modelo.PoisonPill;
import com.tp.modelo.Post;
import com.tp.modelo.PostMessage;

import java.io.InputStream;
import java.io.InputStreamReader;
import java.lang.reflect.Type;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.concurrent.BlockingQueue;
import java.util.logging.Level;
import java.util.logging.Logger;

public class Productor implements Runnable {

    private static final Logger LOG = Logger.getLogger(Productor.class.getName());

    private final BlockingQueue<PipelineMessage> entrada;
    private final int poisonPillsCount;

    public Productor(BlockingQueue<PipelineMessage> entrada, int poisonPillsCount) {
        this.entrada = entrada;
        this.poisonPillsCount = poisonPillsCount;
    }

    @Override
    public void run() {
        try {
            List<Post> posts = cargarPosts();
            LOG.info("Productor cargo " + posts.size() + " posts desde posts.json");

            for (Post p : posts) {
                p.setTimestampEntradaNanos(System.nanoTime());
                entrada.put(new PostMessage(p));
                LOG.fine("Productor inyecto post " + p.getPostId());
            }

            for (int i = 0; i < poisonPillsCount; i++) {
                entrada.put(PoisonPill.INSTANCE);
            }
            LOG.info("Productor termino — inyecto " + posts.size()
                     + " posts y " + poisonPillsCount + " poison pills");
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            LOG.log(Level.WARNING, "Productor interrumpido", e);
        } catch (Exception e) {
            LOG.log(Level.SEVERE, "Error en Productor", e);
        }
    }

    private List<Post> cargarPosts() {
        try (InputStream in = Productor.class.getResourceAsStream("/posts.json")) {
            if (in == null) {
                throw new IllegalStateException("No se encontro posts.json en el classpath");
            }
            try (InputStreamReader reader = new InputStreamReader(in, StandardCharsets.UTF_8)) {
                Type listType = new TypeToken<List<Post>>() {}.getType();
                return new Gson().fromJson(reader, listType);
            }
        } catch (Exception e) {
            throw new RuntimeException("Error al cargar posts.json", e);
        }
    }
}
