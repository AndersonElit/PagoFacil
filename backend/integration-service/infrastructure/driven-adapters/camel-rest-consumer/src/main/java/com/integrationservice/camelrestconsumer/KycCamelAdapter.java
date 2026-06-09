package com.integrationservice.camelrestconsumer;

import com.integrationservice.model.KycConsulta;
import com.integrationservice.model.KycGateway;
import com.integrationservice.model.KycResultado;
import org.apache.camel.ProducerTemplate;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

/** Implementa el puerto KycGateway invocando la ruta Camel. Bridge a Reactor con CompletableFuture. */
@Component
public class KycCamelAdapter implements KycGateway {

    private final ProducerTemplate producerTemplate;

    public KycCamelAdapter(ProducerTemplate producerTemplate) {
        this.producerTemplate = producerTemplate;
    }

    @Override
    public Mono<KycResultado> consultar(KycConsulta consulta) {
        return Mono.fromFuture(
                producerTemplate.asyncRequestBody("direct:kyc", consulta, KycResultado.class));
    }
}
