package com.integrationservice.sagacamel;

import org.apache.camel.builder.RouteBuilder;
import org.springframework.stereotype.Component;

/**
 * Saga 'transfer' (orquestación). El Saga EIP delimita la transacción de larga duración (LRA);
 * cada paso declara su compensación. Completar los pasos según el diseño técnico.
 */
@Component
public class TransferSagaRouteBuilder extends RouteBuilder {

    @Override
    public void configure() {
        from("direct:saga-transfer")
                .routeId("saga-transfer")
                .saga()
                    .compensation("direct:compensar-transfer")
                    .log("Saga 'transfer' iniciada: ${header.sagaId}");
                    // TODO: encadenar los pasos de la saga (to("direct:<paso>")) según el diseño.

        from("direct:compensar-transfer")
                .routeId("compensar-transfer")
                .log("Compensando saga 'transfer': ${header.sagaId}");
                // TODO: invocar los endpoints/consumidores de compensación de los participantes.
    }
}
