# Copyright: (c) 2018, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)

@{
    RootModule = 'PSCSharpInvoker.psm1'
    ModuleVersion = '0.1.0'
    GUID = 'ce1a65db-7619-4975-9572-3b1169b749a0'
    Author = 'Jordan Borean'
    Copyright = 'Copyright (c) 2018 by Jordan Borean, Red Hat, licensed under MIT.'
    Description = "Adds a cmdlet that can be used to invoke C# code without loading the types in the current PowerShell namespace or creating a new process.`nSee https://github.com/jborean93/PSCSharpInvoke for more info"
    PowerShellVersion = '3.0'
    FunctionsToExport = @(
        'Invoke-CSharpMethod'
    )
    PrivateData = @{
        PSData = @{
            Tags = @(
                "DevOps",
                "Windows"
            )
            LicenseUri = 'https://github.com/jborean93/PSCSharpInvoker/blob/master/LICENSE'
            ProjectUri = 'https://github.com/jborean93/PSCSharpInvoker'
            ReleaseNotes = 'See https://github.com/jborean93/PSCSharpInvoker/blob/master/CHANGELOG.md'
        }
    }
}