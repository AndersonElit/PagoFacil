package com.integrationservice.camelrestconsumer;

import org.apache.camel.builder.RouteBuilder;
import org.springframework.stereotype.Component;

/**
 * Ruta Camel hacia el sistema externo 'sms-email' con ACL, reintentos y circuit breaker
 * (Resilience4j). Bridge reactivo en el adaptador; aquí solo mediación e integración.
 */
@Component
public class SmsEmailRouteBuilder extends RouteBuilder {

    @Override
    public void configure() {
        onException(Exception.class)
                .maximumRedeliveries(3)
                .redeliveryDelay(500)
                .handled(true)
                .setBody(constant(null));

        from("direct:smsemail")
                .routeId("sms-email-route")
                .marshal().json()
                .circuitBreaker()
                    .resilience4jConfiguration()
                        .timeoutEnabled(true)
                        .timeoutDuration(3000)
                    .end()
                    .setHeader("CamelHttpMethod", constant("POST"))
                    .toD("{{external.sms-email.base-url}}/consulta?bridgeEndpoint=true&throwExceptionOnFailure=true")
                .endCircuitBreaker()
                .unmarshal().json();
    }
}
