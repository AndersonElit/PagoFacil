package com.integrationservice.model;

import reactor.core.publisher.Mono;

/** Puerto secundario hacia el sistema externo 'aml'. El dominio no conoce Camel. */
public interface AmlGateway {
    Mono<AmlResultado> consultar(AmlConsulta consulta);
}
