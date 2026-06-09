package com.integrationservice.model;

import reactor.core.publisher.Mono;

/** Puerto secundario hacia el sistema externo 'financial-entities'. El dominio no conoce Camel. */
public interface FinancialEntitiesGateway {
    Mono<FinancialEntitiesResultado> consultar(FinancialEntitiesConsulta consulta);
}
