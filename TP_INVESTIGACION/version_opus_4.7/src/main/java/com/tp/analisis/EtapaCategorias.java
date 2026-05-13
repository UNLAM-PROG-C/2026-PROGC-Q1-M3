package com.tp.analisis;

import com.google.gson.Gson;
import com.tp.modelo.PipelineMessage;
import com.tp.modelo.PoisonPill;
import com.tp.modelo.Post;
import com.tp.modelo.PostMessage;

import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.LongAdder;
import java.util.logging.Level;
import java.util.logging.Logger;
import java.util.regex.Pattern;

public class EtapaCategorias {

    private static final Logger LOG = Logger.getLogger(EtapaCategorias.class.getName());
    private static final Pattern TOKEN_SPLIT = Pattern.compile("[^\\p{L}]+");

    private final BlockingQueue<PipelineMessage> entrada;
    private final BlockingQueue<PipelineMessage> salida;
    private final int workers;
    private final int siguientesWorkers;
    private final LongAdder tiempoAcumNanos;
    private final AtomicInteger restantes;

    private final Map<String, Set<String>> diccionarios;

    public EtapaCategorias(BlockingQueue<PipelineMessage> entrada,
                           BlockingQueue<PipelineMessage> salida,
                           int workers,
                           int siguientesWorkers,
                           LongAdder tiempoAcumNanos) {
        this.entrada = entrada;
        this.salida = salida;
        this.workers = workers;
        this.siguientesWorkers = siguientesWorkers;
        this.tiempoAcumNanos = tiempoAcumNanos;
        this.restantes = new AtomicInteger(workers);
        this.diccionarios = cargarDiccionarios();
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
                    if (restantes.decrementAndGet() == 0) {
                        for (int i = 0; i < siguientesWorkers; i++) {
                            salida.put(PoisonPill.INSTANCE);
                        }
                    }
                    return;
                }
                Post post = ((PostMessage) msg).post();
                long inicio = System.nanoTime();
                List<String> categorias = clasificar(post.getTexto());
                post.setCategorias(categorias);
                tiempoAcumNanos.add(System.nanoTime() - inicio);
                LOG.info("Post " + post.getPostId() + " → categorias=" + categorias);
                salida.put(new PostMessage(post));
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            LOG.log(Level.WARNING, "Worker categorias interrumpido", e);
        } catch (Exception e) {
            LOG.log(Level.SEVERE, "Error en worker categorias", e);
        }
    }

    private List<String> clasificar(String texto) {
        List<String> matches = new ArrayList<>();
        if (texto == null || texto.isBlank()) return matches;
        String[] tokens = TOKEN_SPLIT.split(texto.toLowerCase(Locale.ROOT));
        for (Map.Entry<String, Set<String>> entry : diccionarios.entrySet()) {
            Set<String> palabras = entry.getValue();
            for (String t : tokens) {
                if (!t.isEmpty() && palabras.contains(t)) {
                    matches.add(entry.getKey());
                    break;
                }
            }
        }
        return matches;
    }

    @SuppressWarnings("unchecked")
    private Map<String, Set<String>> cargarDiccionarios() {
        try (InputStream in = EtapaCategorias.class.getResourceAsStream("/palabras_prohibidas.json")) {
            if (in == null) {
                throw new IllegalStateException("No se encontro palabras_prohibidas.json");
            }
            try (InputStreamReader r = new InputStreamReader(in, StandardCharsets.UTF_8)) {
                Map<String, List<String>> raw = new Gson().fromJson(r, Map.class);
                Map<String, Set<String>> result = new LinkedHashMap<>();
                for (Map.Entry<String, List<String>> e : raw.entrySet()) {
                    result.put(e.getKey(), new HashSet<>(e.getValue()));
                }
                return result;
            }
        } catch (Exception e) {
            throw new RuntimeException("Error cargando diccionarios prohibidos", e);
        }
    }
}
