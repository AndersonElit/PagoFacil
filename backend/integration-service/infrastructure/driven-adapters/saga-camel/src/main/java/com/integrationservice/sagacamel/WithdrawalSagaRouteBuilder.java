package com.integrationservice.sagacamel;

import org.apache.camel.builder.RouteBuilder;
import org.springframework.stereotype.Component;

/**
 * Saga 'withdrawal' (orquestación). El Saga EIP delimita la transacción de larga duración (LRA);
 * cada paso declara su compensación. Completar los pasos según el diseño técnico.
 */
@Component
public class WithdrawalSagaRouteBuilder extends RouteBuilder {

    @Override
    public void configure() {
        from("direct:saga-withdrawal")
                .routeId("saga-withdrawal")
                .saga()
                    .compensation("direct:compensar-withdrawal")
                    .log("Saga 'withdrawal' iniciada: ${header.sagaId}");
                    // TODO: encadenar los pasos de la saga (to("direct:<paso>")) según el diseño.

        from("direct:compensar-withdrawal")
                .routeId("compensar-withdrawal")
                .log("Compensando saga 'withdrawal': ${header.sagaId}");
                // TODO: invocar los endpoints/consumidores de compensación de los participantes.
    }
}
