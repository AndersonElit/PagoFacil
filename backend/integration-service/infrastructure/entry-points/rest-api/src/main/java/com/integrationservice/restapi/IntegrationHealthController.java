package com.integrationservice.restapi;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;

@RestController
public class IntegrationHealthController {
    @GetMapping("/integration/ping")
    public Mono<String> ping() {
        return Mono.just("integration-service up");
    }
}
