package com.tp.modelo;

import com.google.gson.annotations.SerializedName;

import java.util.List;

public class Post {

    @SerializedName("post_id")
    private int postId;

    @SerializedName("texto")
    private String texto;

    private transient long timestampEntradaNanos;
    private transient String sentimiento;
    private transient List<String> categorias;

    public Post() {}

    public Post(int postId, String texto) {
        this.postId = postId;
        this.texto = texto;
    }

    public int getPostId() { return postId; }
    public String getTexto() { return texto; }

    public long getTimestampEntradaNanos() { return timestampEntradaNanos; }
    public void setTimestampEntradaNanos(long t) { this.timestampEntradaNanos = t; }

    public String getSentimiento() { return sentimiento; }
    public void setSentimiento(String s) { this.sentimiento = s; }

    public List<String> getCategorias() { return categorias; }
    public void setCategorias(List<String> c) { this.categorias = c; }
}
