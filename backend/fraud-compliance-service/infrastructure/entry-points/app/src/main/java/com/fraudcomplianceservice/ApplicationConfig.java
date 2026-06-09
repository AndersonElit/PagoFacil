package com.fraudcomplianceservice;

import org.springframework.context.annotation.ComponentScan;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.FilterType;

@Configuration
@ComponentScan(
        basePackages = {
                "com.fraudcomplianceservice.usecases",
                "com.fraudcomplianceservice.restapi",
                "com.fraudcomplianceservice.app"
        },
        includeFilters = {
                @ComponentScan.Filter(
                        type = FilterType.REGEX,
                        pattern = ".*UseCase?$"
                )
        },
        useDefaultFilters = false
)
public class ApplicationConfig {
}
