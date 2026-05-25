package com.tp.modelo;

public final class PoisonPill implements PipelineMessage {
    public static final PoisonPill INSTANCE = new PoisonPill();
    private PoisonPill() {}
}
