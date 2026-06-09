package com.integrationservice.camelrestconsumer;

import com.integrationservice.model.FinancialEntitiesConsulta;
import com.integrationservice.model.FinancialEntitiesGateway;
import com.integrationservice.model.FinancialEntitiesResultado;
import org.apache.camel.ProducerTemplate;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

/** Implementa el puerto FinancialEntitiesGateway invocando la ruta Camel. Bridge a Reactor con CompletableFuture. */
@Component
public class FinancialEntitiesCamelAdapter implements FinancialEntitiesGateway {

    private final ProducerTemplate producerTemplate;

    public FinancialEntitiesCamelAdapter(ProducerTemplate producerTemplate) {
        this.producerTemplate = producerTemplate;
    }

    @Override
    public Mono<FinancialEntitiesResultado> consultar(FinancialEntitiesConsulta consulta) {
        return Mono.fromFuture(
                producerTemplate.asyncRequestBody("direct:financialentities", consulta, FinancialEntitiesResultado.class));
    }
}
