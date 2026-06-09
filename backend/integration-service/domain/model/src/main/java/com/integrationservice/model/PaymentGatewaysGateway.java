package com.integrationservice.model;

import reactor.core.publisher.Mono;

/** Puerto secundario hacia el sistema externo 'payment-gateways'. El dominio no conoce Camel. */
public interface PaymentGatewaysGateway {
    Mono<PaymentGatewaysResultado> consultar(PaymentGatewaysConsulta consulta);
}
