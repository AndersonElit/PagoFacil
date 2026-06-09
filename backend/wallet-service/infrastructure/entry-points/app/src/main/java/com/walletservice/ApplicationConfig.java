package com.walletservice;

import org.springframework.context.annotation.ComponentScan;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.FilterType;

@Configuration
@ComponentScan(
        basePackages = {
                "com.walletservice.usecases",
                "com.walletservice.restapi",
                "com.walletservice.app"
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
