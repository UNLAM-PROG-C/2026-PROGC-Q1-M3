package com.tp.analisis;

import com.google.gson.Gson;
import com.tp.modelo.PipelineMessage;
import com.tp.modelo.PoisonPill;
import com.tp.modelo.Post;
import com.tp.modelo.PostMessage;

import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.HashSet;
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

public class EtapaSentimiento {

    private static final Logger LOG = Logger.getLogger(EtapaSentimiento.class.getName());
    private static final Pattern TOKEN_SPLIT = Pattern.compile("[^\\p{L}]+");

    private final BlockingQueue<PipelineMessage> entrada;
    private final BlockingQueue<PipelineMessage> salida;
    private final int workers;
    private final int siguientesWorkers;
    private final LongAdder tiempoAcumNanos;

    private final Set<String> positivas;
    private final Set<String> negativas;

    // Solo el ultimo worker en ver una pill propaga las siguientes — garantiza que todos
    // los outputs de esta etapa ya esten en la cola de salida antes de soltar pills.
    private final AtomicInteger restantes;

    public EtapaSentimiento(BlockingQueue<PipelineMessage> entrada,
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

        Map<String, List<String>> lexico = cargarLexico();
        this.positivas = new HashSet<>(lexico.getOrDefault("positivas", List.of()));
        this.negativas = new HashSet<>(lexico.getOrDefault("negativas", List.of()));
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
                String sentimiento = analizar(post.getTexto());
                post.setSentimiento(sentimiento);
                tiempoAcumNanos.add(System.nanoTime() - inicio);
                LOG.info("Post " + post.getPostId() + " → sentimiento=" + sentimiento);
                salida.put(new PostMessage(post));
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            LOG.log(Level.WARNING, "Worker sentimiento interrumpido", e);
        } catch (Exception e) {
            LOG.log(Level.SEVERE, "Error en worker sentimiento", e);
        }
    }

    private String analizar(String texto) {
        if (texto == null || texto.isBlank()) return "neutro";
        String[] tokens = TOKEN_SPLIT.split(texto.toLowerCase(Locale.ROOT));
        int pos = 0, neg = 0;
        for (String t : tokens) {
            if (t.isEmpty()) continue;
            if (positivas.contains(t)) pos++;
            if (negativas.contains(t)) neg++;
        }
        if (pos > neg) return "positivo";
        if (neg > pos) return "negativo";
        return "neutro";
    }

    @SuppressWarnings("unchecked")
    private Map<String, List<String>> cargarLexico() {
        try (InputStream in = EtapaSentimiento.class.getResourceAsStream("/palabras_sentimiento.json")) {
            if (in == null) {
                throw new IllegalStateException("No se encontro palabras_sentimiento.json");
            }
            try (InputStreamReader r = new InputStreamReader(in, StandardCharsets.UTF_8)) {
                return new Gson().fromJson(r, Map.class);
            }
        } catch (Exception e) {
            throw new RuntimeException("Error cargando lexico de sentimiento", e);
        }
    }

}
