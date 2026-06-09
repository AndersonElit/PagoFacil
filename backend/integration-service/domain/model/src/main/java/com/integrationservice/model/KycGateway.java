package com.integrationservice.model;

import reactor.core.publisher.Mono;

/** Puerto secundario hacia el sistema externo 'kyc'. El dominio no conoce Camel. */
public interface KycGateway {
    Mono<KycResultado> consultar(KycConsulta consulta);
}
