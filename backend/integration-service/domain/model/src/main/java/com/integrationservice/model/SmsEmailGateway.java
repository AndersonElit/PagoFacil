package com.integrationservice.model;

import reactor.core.publisher.Mono;

/** Puerto secundario hacia el sistema externo 'sms-email'. El dominio no conoce Camel. */
public interface SmsEmailGateway {
    Mono<SmsEmailResultado> consultar(SmsEmailConsulta consulta);
}
