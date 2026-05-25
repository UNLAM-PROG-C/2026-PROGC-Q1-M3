package com.tp.modelo;

public final class Post implements PipelineMessage {
    private final int postId;
    private final String texto;
    private long timestampInicio;
    private String sentimiento;
    private java.util.List<String> categorias;
    private double spamScore;
    private String decision;

    public Post(int postId, String texto) {
        this.postId = postId;
        this.texto = texto;
        this.timestampInicio = System.nanoTime();
        this.categorias = new java.util.ArrayList<>();
    }

    public int getPostId() {
        return postId;
    }

    public String getTexto() {
        return texto;
    }

    public long getTimestampInicio() {
        return timestampInicio;
    }

    public void setTimestampInicio(long timestampInicio) {
        this.timestampInicio = timestampInicio;
    }

    public String getSentimiento() {
        return sentimiento;
    }

    public void setSentimiento(String sentimiento) {
        this.sentimiento = sentimiento;
    }

    public java.util.List<String> getCategorias() {
        return categorias;
    }

    public void setCategorias(java.util.List<String> categorias) {
        this.categorias = categorias;
    }

    public double getSpamScore() {
        return spamScore;
    }

    public void setSpamScore(double spamScore) {
        this.spamScore = spamScore;
    }

    public String getDecision() {
        return decision;
    }

    public void setDecision(String decision) {
        this.decision = decision;
    }
}
