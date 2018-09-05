# Copyright: (c) 2018, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)

$verbose = @{}
if ($env:APPVEYOR_REPO_BRANCH -and $env:APPVEYOR_REPO_BRANCH -notlike "master") {
    $verbose.Add("Verbose", $true)
}

$ps_version = $PSVersionTable.PSVersion.Major
$module_name = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
$repo_name = (Get-ChildItem -Path $PSScriptRoot\.. -Directory -Exclude Tests).Name
Import-Module -Name $PSScriptRoot\..\$repo_name -Force

Describe "$module_name PS$ps_version tests" {
    Context 'Strict mode' {
        Set-StrictMode -Version latest

        $output_folder = [System.IO.Path]::Combine($PSScriptRoot, "files")

        BeforeEach {
            if (Test-Path -Path $output_folder) {
                Remove-Item -Path $output_folder -Force -Recurse
            }
            New-Item -Path $output_folder -ItemType Directory > $null
        }

        It "Runs a void method with no arguments" {
            $code_template = @"
using System;

namespace PSCSharpInvoker
{{
    public class Testing
    {{
        public static void Method()
        {{
            System.IO.File.Create(@"{0}").Close();
        }}
    }}
}}
"@

            $test_file = [System.IO.Path]::Combine($output_folder, "first")
            $code = $code_template -f $test_file
            Invoke-CSharpMethod -Code $code -Class PSCSharpInvoker.Testing -Method Method
            Test-Path -Path $test_file | Should -Be $true

            # now repeat the same namespace/class but with a different file
            # this proves that the namespace isn't loaded in the current
            # assembly
            $test_file = [System.IO.Path]::Combine($output_folder, "second")
            $code = $code_template -f $test_file
            Invoke-CSharpMethod -Code $code -Class PSCSharpInvoker.Testing -Method Method
            Test-Path -Path $test_file | Should -Be $true
        }

        It "Runs a method with a string return value" {
            $code_template = @"
using System;

public class Testing
{{
    public static string RunMe()
    {{
        return @"{0}";
    }}
}}
"@

            $code = $code_template -f "return value"
            $res = Invoke-CSharpMethod -Code $code -Class Testing -Method RunMe
            $res | Should -Be "return value"

            $code = $code_template -f "return value 2"
            $res = Invoke-CSharpMethod -Code $code -Class Testing -Method RunMe
            $res | Should -Be "return value 2"

            $code = $code_template -f "return value 3"
            $res = Invoke-CSharpMethod -Code $code -Class Testing -Method RunMe -Arguments $null
            $res | Should -Be "return value 3"
        }

        It "Runas a method with multiple classes and methods" {
            $code = @"
using System;

public class Testing1
{
    public static string Method1()
    {
        return "Testing1.Method1";
    }

    public static string Method2()
    {
        return "Testing1.Method2";
    }
}

public class Testing2
{
    public static string Method1()
    {
        return "Testing2.Method1";
    }

    public static string Method3()
    {
        return "Testing2.Method3";
    }
}
"@

            $res = Invoke-CSharpMethod -Code $code -Class Testing1 -Method Method1
            $res | Should -be "Testing1.Method1"

            $res = Invoke-CSharpMethod -Code $code -Class Testing1 -Method Method2
            $res | Should -be "Testing1.Method2"

            $res = Invoke-CSharpMethod -Code $code -Class Testing2 -Method Method1
            $res | Should -be "Testing2.Method1"

            $res = Invoke-CSharpMethod -Code $code -Class Testing2 -Method Method3
            $res | Should -be "Testing2.Method3"
        }

        It "Refers to another assembly" {
            $code = @"
using System;
using System.Collections;
using System.Management.Automation;
using System.Web.Script.Serialization;

public class Foo
{
    public static string Bar()
    {
        JavaScriptSerializer jss = new JavaScriptSerializer();
        if (typeof(PSObject) != typeof(PSObject))
            return "will never fire";
        return jss.Serialize(new Hashtable() { { "a", "b" } });
    }
}
"@

            $actual = { Invoke-CSharpMethod -Code $code -Class Foo -Method Bar } | Should -Throw -PassThru
            $actual | Should -Match "The type or namespace name 'Web' does not exist in the namespace 'System' \(are you missing an assembly reference\?\)"
            $actual.FullyQualifiedErrorId | Should -Be "InvalidOperationException,Invoke-CSharpMethod"
            $actual.Exception.InnerException.GetType().FullName | Should -Be "System.InvalidOperationException"

            $res = Invoke-CSharpMethod -Code $code -Class Foo -Method Bar -ReferencedAssemblies "System.Web.Extensions.dll"
            $res | Should -Be '{"a":"b"}'
        }

        It "Runs a method with a single argument" {
            $code = @"
using System;

public class Testing
{
    public static string RunMe(string arg)
    {
        return arg;
    }
}
"@

            $res = Invoke-CSharpMethod -Code $code -Class Testing -Method RunMe -Arguments "arg1"
            $res | Should -be "arg1"

            $code = @"
using System;

public class Testing
{
    public static int RunMe(int arg)
    {
        return arg;
    }
}
"@

            $res = Invoke-CSharpMethod -Code $code -Class Testing -Method RunMe -Arguments 1
            $res | Should -be 1
        }

        It "Runs a method with a single array argument" {
            $code = @"
using System;

public class Testing
{
    public static string[] RunMe(string[] args)
    {
        return args;
    }
}
"@

            $res = Invoke-CSharpMethod -Code $code -Class Testing -Method RunMe -Arguments @(,[String[]]@("arg1", "arg2"))
            $res | Should -be @("arg1", "arg2")

            $code = @"
using System;

public class Testing
{
    public static int[] RunMe(int[] args)
    {
        return args;
    }
}
"@

            $res = Invoke-CSharpMethod -Code $code -Class Testing -Method RunMe -Arguments @(,[int[]]@(1, 2))
            $res | Should -be @(1, 2)
        }

        It "Runs a method with multiple arguments" {
            $code = @"
using System;

public class Testing
{
    public static string RunMe(string arg1, string arg2)
    {
        return String.Format("'{0}', '{1}'", arg1, arg2);
    }
}
"@

            $res = Invoke-CSharpMethod -Code $code -Class Testing -Method RunMe -Arguments "arg1", "arg2"
            $res | Should -be "'arg1', 'arg2'"

            $code = @"
using System;
using System.Collections.Generic;

public class Testing
{
    public static string RunMe(bool arg1, List<string> arg2)
    {
        return String.Format("'{0}', '{1}'", arg1, String.Join(", ", arg2));
    }
}
"@

            $arg2 = ([System.Collections.Generic.List`1[String]]@("arg1", "arg2"))
            $res = Invoke-CSharpMethod -Code $code -Class Testing -Method RunMe -Arguments $true, $arg2
            $res | Should -be "'True', 'arg1, arg2'"
        }

        It "Runs a method with mutliple array arguments" {
            $code = @"
using System;

public class Testing
{
    public static string RunMe(object[] arg1, string[] arg2)
    {
        return String.Format("'{0}', '{1}'", String.Join(", ", arg1), String.Join(", ", arg2));
    }
}
"@

            $res = Invoke-CSharpMethod -Code $code -Class Testing -Method RunMe -Arguments @(@("arg1", "arg2"), [String[]]@("arg3", "arg4"))
            $res | Should -be "'arg1, arg2', 'arg3, arg4'"

            $code = @"
using System;

public class Testing
{
    public static string Method(params int[] args)
    {
        return String.Join(", ", args);
    }
}
"@

            $res = Invoke-CSharpMethod -Code $code -Class Testing -Method Method -Arguments @(,[int[]]@(1, 2, 3, 4))
            $res | Should -be "1, 2, 3, 4"
        }

        It "Runs a method with default arguments" {
            $code = @"
using System;

public class Foo
{
    public static string Bar(string arg1, string arg2 = "arg2")
    {
        return String.Format("{0}, {1}", arg1, arg2);
    }
}
"@

            $res = Invoke-CSharpMethod -Code $code -Class Foo -Method Bar -Arguments "arg1", ([Type]::Missing)
            $res | Should -be "arg1, arg2"

            $res = Invoke-CSharpMethod -Code $code -Class Foo -Method Bar -Arguments "arg1", "arg3"
            $res | Should -be "arg1, arg3"
        }

        It "Runs a method with a warning failure" {
            $code = @"
using System;

public class Foo
{
    public static void Bar()
    {
        string test = "unused";
        return;
    }
}
"@

            $actual = { Invoke-CSharpMethod -Code $code -Class Foo -Method Bar } | Should -Throw -PassThru
            $actual | Should -Match "The variable 'test' is assigned but its value is never used"
            $actual.FullyQualifiedErrorId | Should -Be "InvalidOperationException,Invoke-CSharpMethod"
            $actual.Exception.InnerException.GetType().FullName | Should -Be "System.InvalidOperationException"
        }

        It "Runs a method with a warning and ignore" {
            $code = @"
using System;

public class Foo
{
    public static void Bar()
    {
        string test = "unused";
        return;
    }
}
"@

            Invoke-CSharpMethod -Code $code -Class Foo -Method Bar -IgnoreWarnings
        }

        It "Failed to compile" {
            $code = @"
using System;

public class Foo
{
    public static void Bar()
    {
        return
    }
}
"@

            $actual = { Invoke-CSharpMethod -Code $code -Class Foo -Method Bar } | Should -Throw -PassThru
            $actual | Should -Match "; expected"
            $actual.FullyQualifiedErrorId | Should -Be "InvalidOperationException,Invoke-CSharpMethod"
            $actual.Exception.InnerException.GetType().FullName | Should -Be "System.InvalidOperationException"
        }

        It "Failed to find class type" {
            $code = @"
using System;

public class Foo
{
    public static void Bar()
    {
        return;
    }
}

public class FooBar2
{
    public static void Bar()
    {
        return;
    }
}
"@

            $actual = { Invoke-CSharpMethod -Code $code -Class FooBar -Method Bar } | Should -Throw -PassThru
            $actual | Should -Match "failed to find the type FooBar in the loaded assembly, found types: Foo, FooBar2"
            $actual.FullyQualifiedErrorId | Should -Be "InvalidOperationException,Invoke-CSharpMethod"
            $actual.Exception.InnerException.GetType().FullName | Should -Be "System.InvalidOperationException"
        }

        It "Failed to find method" {
            $code = @"
using System;

public class Foo
{
    public static void Bar1()
    {
        return;
    }

    public static void Bar2()
    {
        return;
    }
}

public class FooBar
{
    public static void Bar()
    {
        return;
    }
}
"@

            $actual = { Invoke-CSharpMethod -Code $code -Class Foo -Method Bar } | Should -Throw -passThru
            $actual | Should -Match "failed to find the method Bar in the type Foo"
            $actual.FullyQualifiedErrorId | Should -Be "InvalidOperationException,Invoke-CSharpMethod"
            $actual.Exception.InnerException.GetType().FullName | Should -Be "System.InvalidOperationException"
        }

        It "Failed with invalid argument count" {
            $code = @"
using System;

public class Foo
{
    public static void Bar(string arg, int arg2)
    {
        return;
    }
}
"@

            $actual = { Invoke-CSharpMethod -Code $code -Class Foo -Method Bar } | Should -Throw -PassThru
            $actual | Should -Match "Parameter count mismatch."
            $actual | Should -Match "Method parameters (2): String arg, Int32 arg2"
            $actual | Should -Match "Actual parameters (0):"
            $actual.FullyQualifiedErrorId | Should -Be "TargetParameterCountException,Invoke-CSharpMethod"
            $actual.Exception.InnerException.GetType().FullName | Should -Be "System.Reflection.TargetParameterCountException"

            $actual = { Invoke-CSharpMethod -Code $code -Class Foo -Method Bar -Arguments "a" } | Should -Throw -PassThru
            $actual | Should -Match "Parameter count mismatch."
            $actual | Should -Match "Method parameters (2): String arg, Int32 arg2"
            $actual | Should -Match "Actual parameters (1): String"
            $actual.FullyQualifiedErrorId | Should -Be "TargetParameterCountException,Invoke-CSharpMethod"
            $actual.Exception.InnerException.GetType().FullName | Should -Be "System.Reflection.TargetParameterCountException"

            Invoke-CSharpMethod -Code $code -Class Foo -Method Bar -Arguments "a", 1

            $actual = { Invoke-CSharpMethod -Code $code -Class Foo -Method Bar -Arguments "a", 1, "b" } | Should -Throw -PassThru
            $actual | Should -Match "Parameter count mismatch."
            $actual | Should -Match "Method parameters (2): String arg, Int32 arg2"
            $actual | Should -Match "Actual parameters (3): String, Int32, String"
            $actual.FullyQualifiedErrorId | Should -Be "TargetParameterCountException,Invoke-CSharpMethod"
            $actual.Exception.InnerException.GetType().FullName | Should -Be "System.Reflection.TargetParameterCountException"
        }

        AfterEach {
            if (Test-Path -Path $output_folder) {
                Remove-Item -Path $output_folder -Force -Recurse
            }
        }
    }
}