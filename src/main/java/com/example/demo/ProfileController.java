package com.example.demo;

import lombok.RequiredArgsConstructor;
import org.springframework.core.env.Environment;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Arrays;
import java.util.List;

@RequiredArgsConstructor
@RestController
public class ProfileController {

    private final Environment env;

    @GetMapping("/profile")
    public String profile() {
        // 현재 실행 중인 ActiveProfile을 모두 가져옴
        List<String> profiles = Arrays.asList(env.getActiveProfiles());

        // real, real1, real2 중 하나라도 있으면 그 값을 반환
        // (real1이 켜져있는지 real2가 켜져있는지 확인하기 위함)
        List<String> realProfiles = Arrays.asList("real", "real1", "real2");

        String defaultProfile = profiles.isEmpty() ? "default" : profiles.get(0);

        return profiles.stream()
            .filter(realProfiles::contains)
            .findAny()
            .orElse(defaultProfile);
    }
}