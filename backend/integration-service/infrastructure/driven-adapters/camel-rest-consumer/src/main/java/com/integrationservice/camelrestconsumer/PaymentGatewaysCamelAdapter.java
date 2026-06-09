package com.integrationservice.camelrestconsumer;

import com.integrationservice.model.PaymentGatewaysConsulta;
import com.integrationservice.model.PaymentGatewaysGateway;
import com.integrationservice.model.PaymentGatewaysResultado;
import org.apache.camel.ProducerTemplate;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

/** Implementa el puerto PaymentGatewaysGateway invocando la ruta Camel. Bridge a Reactor con CompletableFuture. */
@Component
public class PaymentGatewaysCamelAdapter implements PaymentGatewaysGateway {

    private final ProducerTemplate producerTemplate;

    public PaymentGatewaysCamelAdapter(ProducerTemplate producerTemplate) {
        this.producerTemplate = producerTemplate;
    }

    @Override
    public Mono<PaymentGatewaysResultado> consultar(PaymentGatewaysConsulta consulta) {
        return Mono.fromFuture(
                producerTemplate.asyncRequestBody("direct:paymentgateways", consulta, PaymentGatewaysResultado.class));
    }
}
