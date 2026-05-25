package com.tp.modelo;

import com.google.gson.annotations.SerializedName;
import java.util.List;

public class Resultado {
    @SerializedName("post_id")
    private int postId;

    @SerializedName("texto")
    private String texto;

    @SerializedName("spam_score")
    private double spamScore;

    @SerializedName("sentimiento")
    private String sentimiento;

    @SerializedName("categorias")
    private List<String> categorias;

    @SerializedName("decision")
    private String decision;

    @SerializedName("tiempo_procesamiento_ms")
    private long tiempoProcesamientoMs;

    public Resultado() {
    }

    public Resultado(int postId, String texto, double spamScore, String sentimiento,
                     List<String> categorias, String decision, long tiempoProcesamientoMs) {
        this.postId = postId;
        this.texto = texto;
        this.spamScore = spamScore;
        this.sentimiento = sentimiento;
        this.categorias = categorias;
        this.decision = decision;
        this.tiempoProcesamientoMs = tiempoProcesamientoMs;
    }

    public int getPostId() {
        return postId;
    }

    public void setPostId(int postId) {
        this.postId = postId;
    }

    public String getTexto() {
        return texto;
    }

    public void setTexto(String texto) {
        this.texto = texto;
    }

    public double getSpamScore() {
        return spamScore;
    }

    public void setSpamScore(double spamScore) {
        this.spamScore = spamScore;
    }

    public String getSentimiento() {
        return sentimiento;
    }

    public void setSentimiento(String sentimiento) {
        this.sentimiento = sentimiento;
    }

    public List<String> getCategorias() {
        return categorias;
    }

    public void setCategorias(List<String> categorias) {
        this.categorias = categorias;
    }

    public String getDecision() {
        return decision;
    }

    public void setDecision(String decision) {
        this.decision = decision;
    }

    public long getTiempoProcesamientoMs() {
        return tiempoProcesamientoMs;
    }

    public void setTiempoProcesamientoMs(long tiempoProcesamientoMs) {
        this.tiempoProcesamientoMs = tiempoProcesamientoMs;
    }
}
