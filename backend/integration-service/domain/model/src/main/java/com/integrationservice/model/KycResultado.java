package com.integrationservice.model;

/** Respuesta de dominio desde 'kyc' (traducida por el ACL del adaptador). */
public record KycResultado(String referencia, String estado, java.util.Map<String, Object> datos) {}
