package com.integrationservice.model;

/** Respuesta de dominio desde 'payment-gateways' (traducida por el ACL del adaptador). */
public record PaymentGatewaysResultado(String referencia, String estado, java.util.Map<String, Object> datos) {}
