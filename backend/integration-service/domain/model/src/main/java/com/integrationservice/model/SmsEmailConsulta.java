package com.integrationservice.model;

/** Solicitud de dominio hacia 'sms-email' (modelo propio, no del sistema externo). */
public record SmsEmailConsulta(String referencia, java.util.Map<String, Object> datos) {}
