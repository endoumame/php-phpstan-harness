<?php

declare(strict_types=1);

namespace App;

final class Example
{
    public function greet(string $name): string
    {
        return "Hello, {$name}!";
    }
}
