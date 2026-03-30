<?php

declare(strict_types=1);

namespace App\Tests\Unit;

use App\Example;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

/**
 * @internal
 */
final class ExampleTest extends TestCase
{
    /**
     * @throws \PHPUnit\Framework\ExpectationFailedException
     */
    #[Test]
    public function greetReturnsHelloMessage(): void
    {
        $example = new Example();

        self::assertSame('Hello, World!', $example->greet('World'));
    }
}
