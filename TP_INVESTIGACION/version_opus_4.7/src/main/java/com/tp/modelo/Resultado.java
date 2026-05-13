package com.tp.modelo;

import com.google.gson.annotations.SerializedName;

import java.util.List;

public class Resultado {

    @SerializedName("post_id")
    private final int postId;

    @SerializedName("texto")
    private final String texto;

    @SerializedName("spam_score")
    private final double spamScore;

    @SerializedName("sentimiento")
    private final String sentimiento;

    @SerializedName("categorias")
    private final List<String> categorias;

    @SerializedName("decision")
    private final String decision;

    @SerializedName("tiempo_procesamiento_ms")
    private final long tiempoProcesamientoMs;

    public Resultado(int postId,
                     String texto,
                     double spamScore,
                     String sentimiento,
                     List<String> categorias,
                     String decision,
                     long tiempoProcesamientoMs) {
        this.postId = postId;
        this.texto = texto;
        this.spamScore = spamScore;
        this.sentimiento = sentimiento;
        this.categorias = categorias;
        this.decision = decision;
        this.tiempoProcesamientoMs = tiempoProcesamientoMs;
    }

    public long getTiempoProcesamientoMs() { return tiempoProcesamientoMs; }
}
