package com.brunopc.spring_boot_starter;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class StarterController {

    @GetMapping("/")
	public String index() {
		return "String-boot started! -from brunopc";
	}
}