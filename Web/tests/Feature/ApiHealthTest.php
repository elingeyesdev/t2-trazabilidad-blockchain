<?php

namespace Tests\Feature;

use Tests\TestCase;

class ApiHealthTest extends TestCase
{
    public function test_health_endpoint_is_public_and_accessible_from_flutter_web(): void
    {
        $this->getJson('/api/test-api', [
            'Origin' => 'http://127.0.0.1:8787',
        ])
            ->assertOk()
            ->assertExactJson(['ok' => true])
            ->assertHeader('Access-Control-Allow-Origin', '*');
    }

    public function test_api_accepts_cors_preflight_for_json_and_bearer_headers(): void
    {
        $this->options('/api/test-api', [], [
            'Origin' => 'http://127.0.0.1:8787',
            'Access-Control-Request-Method' => 'GET',
            'Access-Control-Request-Headers' => 'accept,authorization,content-type',
        ])
            ->assertNoContent()
            ->assertHeader('Access-Control-Allow-Origin', '*')
            ->assertHeader(
                'Access-Control-Allow-Headers',
                'accept,authorization,content-type'
            );
    }
}
