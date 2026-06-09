package com.integrationservice.model;

/** Solicitud de dominio hacia 'aml' (modelo propio, no del sistema externo). */
public record AmlConsulta(String referencia, java.util.Map<String, Object> datos) {}
