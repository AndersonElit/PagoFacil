package com.integrationservice.model;

/** Respuesta de dominio desde 'sms-email' (traducida por el ACL del adaptador). */
public record SmsEmailResultado(String referencia, String estado, java.util.Map<String, Object> datos) {}
