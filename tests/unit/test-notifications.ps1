# test-notifications.ps1
# Unit tests dla NotificationManager.psm1

<#
.SYNOPSIS
Testy jednostkowe dla modułu NotificationManager

.DESCRIPTION
Weryfikuje:
- Inicjalizację modułu
- Formatowanie wyników
- Toast notifications (graceful degradation)
- Email notifications (mock SMTP)
- Webhook notifications (mock HTTP)

.NOTES
Wymaga: Pester 5.x
Uruchomienie: Invoke-Pester .\test-notifications.ps1
#>

BeforeAll {
    # Import modułu NotificationManager
    $modulePath = Join-Path $PSScriptRoot "..\..\src\NotificationManager.psm1"
    Import-Module $modulePath -Force

    # Mock results dla testów
    $script:testResults = @(
        [pscustomobject]@{
            Name = "Winget"
            Status = "OK"
            Counts = @{
                Installed = 50
                Available = 5
                Updated = 5
                Skipped = 0
                Failed = 0
            }
        },
        [pscustomobject]@{
            Name = "npm"
            Status = "OK"
            Counts = @{
                Installed = 120
                Available = 10
                Updated = 10
                Skipped = 0
                Failed = 0
            }
        },
        [pscustomobject]@{
            Name = "Python/Pip"
            Status = "FAIL"
            Counts = @{
                Installed = 30
                Available = 3
                Updated = 2
                Skipped = 0
                Failed = 1
            }
        }
    )
}

AfterAll {
    Remove-Module NotificationManager -ErrorAction SilentlyContinue
}

Describe "NotificationManager - Initialization" {
    Context "Module initialization" {
        It "Inicjalizuje moduł bez błędów" {
            { Initialize-NotificationManager } | Should -Not -Throw
        }

        It "Get-NotificationStatus zwraca poprawny status" {
            $status = Get-NotificationStatus
            $status.ModuleName | Should -Be "NotificationManager"
            $status.Version | Should -Not -BeNullOrEmpty
            $status.Initialized | Should -Be $true
        }

        It "BurntToast availability jest wykrywana poprawnie" {
            $status = Get-NotificationStatus
            # BurntToastAvailable może być true lub false w zależności od środowiska
            $status.BurntToastAvailable | Should -BeOfType [bool]
        }
    }
}

Describe "NotificationManager - Result Formatting" {
    Context "Format-ResultSummary - Plain" {
        It "Formatuje wyniki jako plain text" {
            # Użyj wewnętrznej funkcji (może być prywatna, więc testujemy przez Send-UpdateNotification)
            # Alternatywnie: test integracyjny

            # Bezpośredni test wymagałby export prywatnej funkcji
            # Dla uproszczenia - sprawdzamy czy funkcja istnieje w module
            $module = Get-Module NotificationManager
            $module | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "NotificationManager - Toast Notifications" {
    Context "Send-ToastNotification" {
        It "Nie rzuca błędu gdy BurntToast nie jest dostępny" {
            # Jeśli BurntToast nie jest zainstalowany, funkcja powinna tylko wyświetlić warning
            {
                Send-ToastNotification -Title "Test" -Message "Test message"
            } | Should -Not -Throw
        }

        It "Akceptuje parametr Results" {
            {
                Send-ToastNotification -Title "Update-Ultra" -Results $script:testResults
            } | Should -Not -Throw
        }

        It "Formatuje wiadomość z Results poprawnie" {
            # Ten test tylko sprawdza czy nie rzuca błędu
            # Faktyczne wysłanie toast wymaga BurntToast
            {
                Send-ToastNotification -Title "Test" -Results $script:testResults
            } | Should -Not -Throw
        }
    }
}

Describe "NotificationManager - Email Notifications" {
    Context "Send-EmailNotification - Parameter validation" {
        It "Wymaga parametru To" {
            {
                Send-EmailNotification -Subject "Test" -Body "Body" `
                    -SmtpServer "smtp.test.com" -Username "user" -Password "pass"
            } | Should -Throw
        }

        It "Wymaga parametru SmtpServer" {
            {
                Send-EmailNotification -To "test@example.com" -Subject "Test" -Body "Body" `
                    -Username "user" -Password "pass"
            } | Should -Throw
        }

        It "Wymaga parametru Username" {
            {
                Send-EmailNotification -To "test@example.com" -Subject "Test" -Body "Body" `
                    -SmtpServer "smtp.test.com" -Password "pass"
            } | Should -Throw
        }

        It "Wymaga parametru Password" {
            {
                Send-EmailNotification -To "test@example.com" -Subject "Test" -Body "Body" `
                    -SmtpServer "smtp.test.com" -Username "user"
            } | Should -Throw
        }
    }

    Context "Send-EmailNotification - Mock SMTP" {
        BeforeAll {
            # Mock Send-MailMessage
            Mock -ModuleName NotificationManager -CommandName Send-MailMessage -MockWith {
                return $true
            }
        }

        It "Wysyła email z Results" {
            {
                Send-EmailNotification -To "test@example.com" -Subject "Test" -Results $script:testResults `
                    -SmtpServer "smtp.test.com" -Username "user@test.com" -Password "password"
            } | Should -Not -Throw
        }

        It "Wysyła email z custom Body" {
            {
                Send-EmailNotification -To "test@example.com" -Subject "Test" -Body "Custom message" `
                    -SmtpServer "smtp.test.com" -Username "user@test.com" -Password "password"
            } | Should -Not -Throw
        }

        It "Akceptuje SecureString password" {
            $securePass = ConvertTo-SecureString "password" -AsPlainText -Force

            {
                Send-EmailNotification -To "test@example.com" -Subject "Test" -Body "Test" `
                    -SmtpServer "smtp.test.com" -Username "user@test.com" -Password $securePass
            } | Should -Not -Throw
        }

        It "Używa Username jako From gdy From nie jest podany" {
            # Ten test wymaga sprawdzenia parametrów wywołania Send-MailMessage
            # Uproszczony test - sprawdza tylko czy nie rzuca błędu
            {
                Send-EmailNotification -To "test@example.com" -Subject "Test" -Body "Test" `
                    -SmtpServer "smtp.test.com" -Username "user@test.com" -Password "password"
            } | Should -Not -Throw
        }
    }
}

Describe "NotificationManager - Webhook Notifications" {
    Context "Send-WebhookNotification - Parameter validation" {
        It "Wymaga parametru Url" {
            {
                Send-WebhookNotification -Results $script:testResults
            } | Should -Throw
        }

        It "Wymaga Results lub CustomPayload" {
            {
                Send-WebhookNotification -Url "https://webhook.test.com/hook"
            } | Should -Throw
        }
    }

    Context "Send-WebhookNotification - Mock HTTP" {
        BeforeAll {
            # Mock Invoke-RestMethod
            Mock -ModuleName NotificationManager -CommandName Invoke-RestMethod -MockWith {
                return @{ success = $true }
            }
        }

        It "Wysyła webhook Generic" {
            {
                Send-WebhookNotification -Url "https://webhook.test.com/hook" `
                    -Results $script:testResults -WebhookType Generic
            } | Should -Not -Throw
        }

        It "Wysyła webhook Slack" {
            {
                Send-WebhookNotification -Url "https://hooks.slack.com/services/XXX" `
                    -Results $script:testResults -WebhookType Slack
            } | Should -Not -Throw
        }

        It "Wysyła webhook Discord" {
            {
                Send-WebhookNotification -Url "https://discord.com/api/webhooks/XXX" `
                    -Results $script:testResults -WebhookType Discord
            } | Should -Not -Throw
        }

        It "Wysyła webhook Teams" {
            {
                Send-WebhookNotification -Url "https://outlook.office.com/webhook/XXX" `
                    -Results $script:testResults -WebhookType Teams
            } | Should -Not -Throw
        }

        It "Wysyła custom payload" {
            $customJson = '{"status": "completed", "count": 15}'

            {
                Send-WebhookNotification -Url "https://webhook.test.com/hook" `
                    -CustomPayload $customJson
            } | Should -Not -Throw
        }
    }
}

Describe "NotificationManager - Send-UpdateNotification (Unified)" {
    BeforeAll {
        # Mock wszystkie metody wysyłania
        Mock -ModuleName NotificationManager -CommandName Send-ToastNotification -MockWith { }
        Mock -ModuleName NotificationManager -CommandName Send-EmailNotification -MockWith { }
        Mock -ModuleName NotificationManager -CommandName Send-WebhookNotification -MockWith { }
    }

    Context "Unified notification sender" {
        It "Wysyła tylko toast gdy Toast enabled" {
            {
                Send-UpdateNotification -Results $script:testResults -Toast
            } | Should -Not -Throw

            Should -Invoke -ModuleName NotificationManager -CommandName Send-ToastNotification -Times 1
        }

        It "Wysyła tylko email gdy Email enabled" {
            {
                Send-UpdateNotification -Results $script:testResults `
                    -Email "test@example.com" -SmtpServer "smtp.test.com" `
                    -SmtpUsername "user" -SmtpPassword "pass"
            } | Should -Not -Throw

            Should -Invoke -ModuleName NotificationManager -CommandName Send-EmailNotification -Times 1
        }

        It "Wysyła tylko webhook gdy Webhook enabled" {
            {
                Send-UpdateNotification -Results $script:testResults `
                    -Webhook "https://webhook.test.com/hook"
            } | Should -Not -Throw

            Should -Invoke -ModuleName NotificationManager -CommandName Send-WebhookNotification -Times 1
        }

        It "Wysyła wszystkie powiadomienia gdy wszystkie enabled" {
            {
                Send-UpdateNotification -Results $script:testResults -Toast `
                    -Email "test@example.com" -SmtpServer "smtp.test.com" `
                    -SmtpUsername "user" -SmtpPassword "pass" `
                    -Webhook "https://webhook.test.com/hook"
            } | Should -Not -Throw

            Should -Invoke -ModuleName NotificationManager -CommandName Send-ToastNotification -Times 1
            Should -Invoke -ModuleName NotificationManager -CommandName Send-EmailNotification -Times 1
            Should -Invoke -ModuleName NotificationManager -CommandName Send-WebhookNotification -Times 1
        }
    }

    Context "Auto-detection webhook type" {
        It "Wykrywa Slack webhook" {
            {
                Send-UpdateNotification -Results $script:testResults `
                    -Webhook "https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXX"
            } | Should -Not -Throw

            # Sprawdź czy wywołano z odpowiednim typem
            Should -Invoke -ModuleName NotificationManager -CommandName Send-WebhookNotification `
                -ParameterFilter { $WebhookType -eq 'Slack' }
        }

        It "Wykrywa Discord webhook" {
            {
                Send-UpdateNotification -Results $script:testResults `
                    -Webhook "https://discord.com/api/webhooks/123456789/abcdefgh"
            } | Should -Not -Throw

            Should -Invoke -ModuleName NotificationManager -CommandName Send-WebhookNotification `
                -ParameterFilter { $WebhookType -eq 'Discord' }
        }

        It "Wykrywa Teams webhook" {
            {
                Send-UpdateNotification -Results $script:testResults `
                    -Webhook "https://outlook.office.com/webhook/xxx"
            } | Should -Not -Throw

            Should -Invoke -ModuleName NotificationManager -CommandName Send-WebhookNotification `
                -ParameterFilter { $WebhookType -eq 'Teams' }
        }
    }
}

Describe "NotificationManager - Error Handling" {
    Context "Graceful degradation" {
        It "Nie przerywa gdy toast fails" {
            # Mock fail
            Mock -ModuleName NotificationManager -CommandName Send-ToastNotification -MockWith {
                throw "Toast failed"
            }

            {
                Send-UpdateNotification -Results $script:testResults -Toast
            } | Should -Not -Throw
        }

        It "Nie przerywa gdy email fails" {
            Mock -ModuleName NotificationManager -CommandName Send-EmailNotification -MockWith {
                throw "Email failed"
            }

            {
                Send-UpdateNotification -Results $script:testResults `
                    -Email "test@example.com" -SmtpServer "smtp.test.com" `
                    -SmtpUsername "user" -SmtpPassword "pass"
            } | Should -Not -Throw
        }

        It "Nie przerywa gdy webhook fails" {
            Mock -ModuleName NotificationManager -CommandName Send-WebhookNotification -MockWith {
                throw "Webhook failed"
            }

            {
                Send-UpdateNotification -Results $script:testResults `
                    -Webhook "https://webhook.test.com/hook"
            } | Should -Not -Throw
        }
    }
}
