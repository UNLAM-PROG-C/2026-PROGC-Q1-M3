package com.tp.modelo;

public sealed interface PipelineMessage permits Post, PoisonPill {
}
