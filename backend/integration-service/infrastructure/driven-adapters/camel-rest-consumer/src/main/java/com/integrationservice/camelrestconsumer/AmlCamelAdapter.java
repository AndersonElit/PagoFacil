package com.integrationservice.camelrestconsumer;

import com.integrationservice.model.AmlConsulta;
import com.integrationservice.model.AmlGateway;
import com.integrationservice.model.AmlResultado;
import org.apache.camel.ProducerTemplate;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

/** Implementa el puerto AmlGateway invocando la ruta Camel. Bridge a Reactor con CompletableFuture. */
@Component
public class AmlCamelAdapter implements AmlGateway {

    private final ProducerTemplate producerTemplate;

    public AmlCamelAdapter(ProducerTemplate producerTemplate) {
        this.producerTemplate = producerTemplate;
    }

    @Override
    public Mono<AmlResultado> consultar(AmlConsulta consulta) {
        return Mono.fromFuture(
                producerTemplate.asyncRequestBody("direct:aml", consulta, AmlResultado.class));
    }
}
