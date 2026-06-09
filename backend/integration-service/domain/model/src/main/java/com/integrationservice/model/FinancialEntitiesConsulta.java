package com.integrationservice.model;

/** Solicitud de dominio hacia 'financial-entities' (modelo propio, no del sistema externo). */
public record FinancialEntitiesConsulta(String referencia, java.util.Map<String, Object> datos) {}
