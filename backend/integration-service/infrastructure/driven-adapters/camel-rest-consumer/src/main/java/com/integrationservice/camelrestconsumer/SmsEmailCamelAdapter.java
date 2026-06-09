package com.integrationservice.camelrestconsumer;

import com.integrationservice.model.SmsEmailConsulta;
import com.integrationservice.model.SmsEmailGateway;
import com.integrationservice.model.SmsEmailResultado;
import org.apache.camel.ProducerTemplate;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

/** Implementa el puerto SmsEmailGateway invocando la ruta Camel. Bridge a Reactor con CompletableFuture. */
@Component
public class SmsEmailCamelAdapter implements SmsEmailGateway {

    private final ProducerTemplate producerTemplate;

    public SmsEmailCamelAdapter(ProducerTemplate producerTemplate) {
        this.producerTemplate = producerTemplate;
    }

    @Override
    public Mono<SmsEmailResultado> consultar(SmsEmailConsulta consulta) {
        return Mono.fromFuture(
                producerTemplate.asyncRequestBody("direct:smsemail", consulta, SmsEmailResultado.class));
    }
}
