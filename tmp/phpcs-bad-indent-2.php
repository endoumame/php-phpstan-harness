<?php

namespace HookTest;

final class PhpcsBadIndentTwo
{
    public function greet(string $name): string
    {
        if ($name === '') {
            return 'empty';
        }

        return "Hello, {$name}";
    }
}
