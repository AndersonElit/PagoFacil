package com.integrationservice.model;

/** Solicitud de dominio hacia 'payment-gateways' (modelo propio, no del sistema externo). */
public record PaymentGatewaysConsulta(String referencia, java.util.Map<String, Object> datos) {}
