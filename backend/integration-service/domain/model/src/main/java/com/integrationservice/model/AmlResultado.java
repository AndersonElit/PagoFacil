package com.integrationservice.model;

/** Respuesta de dominio desde 'aml' (traducida por el ACL del adaptador). */
public record AmlResultado(String referencia, String estado, java.util.Map<String, Object> datos) {}
