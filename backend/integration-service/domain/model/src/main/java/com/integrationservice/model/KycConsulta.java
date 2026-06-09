package com.integrationservice.model;

/** Solicitud de dominio hacia 'kyc' (modelo propio, no del sistema externo). */
public record KycConsulta(String referencia, java.util.Map<String, Object> datos) {}
