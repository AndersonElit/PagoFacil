package com.integrationservice.camelrestconsumer;

import org.apache.camel.builder.RouteBuilder;
import org.springframework.stereotype.Component;

/**
 * Ruta Camel hacia el sistema externo 'payment-gateways' con ACL, reintentos y circuit breaker
 * (Resilience4j). Bridge reactivo en el adaptador; aquí solo mediación e integración.
 */
@Component
public class PaymentGatewaysRouteBuilder extends RouteBuilder {

    @Override
    public void configure() {
        onException(Exception.class)
                .maximumRedeliveries(3)
                .redeliveryDelay(500)
                .handled(true)
                .setBody(constant(null));

        from("direct:paymentgateways")
                .routeId("payment-gateways-route")
                .marshal().json()
                .circuitBreaker()
                    .resilience4jConfiguration()
                        .timeoutEnabled(true)
                        .timeoutDuration(3000)
                    .end()
                    .setHeader("CamelHttpMethod", constant("POST"))
                    .toD("{{external.payment-gateways.base-url}}/consulta?bridgeEndpoint=true&throwExceptionOnFailure=true")
                .endCircuitBreaker()
                .unmarshal().json();
    }
}
