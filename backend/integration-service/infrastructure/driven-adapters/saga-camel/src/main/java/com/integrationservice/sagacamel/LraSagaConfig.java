package com.integrationservice.sagacamel;

import org.apache.camel.service.lra.LRASagaService;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** Registra el servicio de saga LRA (coordinador Narayana) usado por el Saga EIP de Camel. */
@Configuration
public class LraSagaConfig {

    @Bean
    public LRASagaService lraSagaService(
            @Value("${camel.lra.coordinator-url}") String coordinatorUrl,
            @Value("${server.port:8090}") int localPort) {
        LRASagaService service = new LRASagaService();
        service.setCoordinatorUrl(coordinatorUrl);
        service.setLocalParticipantUrl("http://localhost:" + localPort);
        return service;
    }
}
