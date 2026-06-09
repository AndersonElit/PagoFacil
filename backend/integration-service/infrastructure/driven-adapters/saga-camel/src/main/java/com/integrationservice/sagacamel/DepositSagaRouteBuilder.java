package com.integrationservice.sagacamel;

import org.apache.camel.builder.RouteBuilder;
import org.springframework.stereotype.Component;

/**
 * Saga 'deposit' (orquestación). El Saga EIP delimita la transacción de larga duración (LRA);
 * cada paso declara su compensación. Completar los pasos según el diseño técnico.
 */
@Component
public class DepositSagaRouteBuilder extends RouteBuilder {

    @Override
    public void configure() {
        from("direct:saga-deposit")
                .routeId("saga-deposit")
                .saga()
                    .compensation("direct:compensar-deposit")
                    .log("Saga 'deposit' iniciada: ${header.sagaId}");
                    // TODO: encadenar los pasos de la saga (to("direct:<paso>")) según el diseño.

        from("direct:compensar-deposit")
                .routeId("compensar-deposit")
                .log("Compensando saga 'deposit': ${header.sagaId}");
                // TODO: invocar los endpoints/consumidores de compensación de los participantes.
    }
}
