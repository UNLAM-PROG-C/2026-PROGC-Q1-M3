package com.tp;

import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.tp.modelo.Post;
import com.tp.modelo.PoisonPill;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.concurrent.BlockingQueue;
import java.util.logging.Logger;

public class Productor implements Runnable {
    private static final Logger logger = Logger.getLogger(Productor.class.getName());
    private final BlockingQueue<Object> queueIn;
    private final int kA;

    public Productor(BlockingQueue<Object> queueIn, int kA) {
        this.queueIn = queueIn;
        this.kA = kA;
    }

    @Override
    public void run() {
        try {
            Gson gson = new Gson();
            BufferedReader reader = new BufferedReader(
                    new InputStreamReader(getClass().getResourceAsStream("/posts.json")));
            StringBuilder sb = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                sb.append(line);
            }
            reader.close();

            JsonArray posts = gson.fromJson(sb.toString(), JsonArray.class);
            for (JsonElement element : posts) {
                JsonObject obj = element.getAsJsonObject();
                int postId = obj.get("post_id").getAsInt();
                String texto = obj.get("texto").getAsString();
                Post post = new Post(postId, texto);
                post.setTimestampInicio(System.nanoTime());

                queueIn.put(post);
                logger.info("Productor inyectó post_id=" + postId);
            }

            // Inyectar K_A poison pills
            for (int i = 0; i < kA; i++) {
                queueIn.put(PoisonPill.INSTANCE);
                logger.info("Productor inyectó poison pill " + (i + 1) + "/" + kA);
            }

        } catch (Exception e) {
            logger.severe("Error en Productor: " + e.getMessage());
            e.printStackTrace();
        }
    }
}
