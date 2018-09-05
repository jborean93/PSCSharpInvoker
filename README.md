# PSCSharpInvoker

[![Build status](https://ci.appveyor.com/api/projects/status/8q85sya4hvu16e99?svg=true)](https://ci.appveyor.com/project/jborean93/pscsharpinvoker)
[![PowerShell Gallery](https://img.shields.io/powershellgallery/dt/PSCSharpInvoker.svg)](https://www.powershellgallery.com/packages/PSCSharpInvoker)

PowerShell module that allows you to invoke dynamic C# code in the same
process. Usually when using [Add-Type](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/add-type?view=powershell-6),
the compiled C# types are loaded in the current process and there is no way to
unload these types unless you create a new process. This module allows you to
bypass this restriction and invoke C# code even if the type implementation
changes.


## Info

PowerShell is a .NET application which means it is subject to the same
limitations. One of these limitations is that you are unable to define two
different types of the same name. Another issue is that once a type is loaded
in the AppDomain, it is unable to be unloaded. This is why you cannot do the
following;

```
Add-Type -TypeDefinition @'
using System;

public class Foo
{
    public static string Run()
    {
        return "I ran";
    }
}
'@

[Foo]::Run()

Add-Type -TypeDefinition @'
using System;

public class Foo
{
    public static string Run()
    {
        return "I ran again";
    }
}
'@

Add-Type : Cannot add type. The type name 'Foo' already exists.
At line:1 char:1
+ Add-Type -TypeDefinition @'
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : InvalidOperation: (Foo:String) [Add-Type], Exception
    + FullyQualifiedErrorId : TYPE_ALREADY_EXISTS,Microsoft.PowerShell.Commands.AddTypeCommand
```

Traditionally the only way this is designed to work is to run the `Add-Type`
code with different type implementations is to run it in a separate process.
Another, less widely known, way is to create a new AppDomain, load the types in
that separate domain and then run it there. Because the types are never loaded
in the default PowerShell AppDomain we are able to keep on loading the type as
long as the AppDomain is new in every invocation.

The benefits of this approach is that;

* It is a lot quicker than using `Start-Job`, 2 seconds vs 0.3 seconds
* You can easily pass .NET objects to the method like you would when using `Add-Type`

There are some limitations with this approach such as;

* It is only designed to run static methods
* The arguments and return values must have the [SerializableAttribute](https://docs.microsoft.com/en-us/dotnet/api/system.serializableattribute?view=netframework-4.7.2) attribute

The cmdlet `Invoke-CSharpMethod` does all the hard work in setting up a
separate AppDomain, loading the specified C# code and invoking it in that new
AppDomain.


### Invoke-CSharpMethod

Invokes the C# code at the method supplied and output the return value.

#### Syntax

```
Invoke-CSharpMethod
    -Code <String>
    -Class <String>
    -Method <String>
    -IgnoreWarnings <Switch>
    [[-ReferencedAssemblies] <String[]>]
    [[-Arguments] <Object>]
```

#### Parameters

* `Code`: <String> The C# code to run, this should include the `using` assemblies as well as the namespace/class to run
* `Class`: <String> The full name of the class the method to run is located in.
* `Method`: <String> The name of the method to run
* `IgnoreWarnings`: <Switch> By default the module will fail to run if the C# code fire any warnings during compilation, this flag overrides this behavioour and will continue to run even with warnings

#### Optional Parameters

* `ReferencedAssemblies`: <String[]> A list of assembly locations to reference
* `Arguments`: <Object> Any extra arguments to pass onto the function.

#### Input

None

#### Output

The output depends on the method that was run. The cmdlet will return whatever
return value is received from the method.


## Requirements

These cmdlets have the following requirements

* PowerShell v3.0 or newer
* Windows PowerShell (not PowerShell Core)
* Windows Server 2008 R2/Windows 7 or newer


## Installing

The easiest way to install this module is through
[PowerShellGet](https://docs.microsoft.com/en-us/powershell/gallery/overview).
This is installed by default with PowerShell 5 but can be added on PowerShell
3 or 4 by installing the MSI [here](https://www.microsoft.com/en-us/download/details.aspx?id=51451).

Once installed, you can install this module by running;

```
# Install for all users
Install-Module -Name PSCSharpInvoker

# Install for only the current user
Install-Module -Name PSCSharpInvoker -Scope CurrentUser
```

If you wish to remove the module, just run
`Uninstall-Module -Name PSCSharpInvoker`.

If you cannot use PowerShellGet, you can still install the module manually,
here are some basic steps on how to do this;

1. Download the latext zip from GitHub [here](https://github.com/jborean93/PSCSharpInvoker/releases/latest)
2. Extract the zip
3. Copy the folder `PSCSharpInvoker` inside the zip to a path that is set in `$env:PSModulePath`. By default this could be `C:\Program Files\WindowsPowerShell\Modules` or `C:\Users\<user>\Documents\WindowsPowerShell\Modules`
4. Reopen PowerShell and unblock the downloaded files with `$path = (Get-Module -Name PSCSharpInvoker -ListAvailable).ModuleBase; Unblock-File -Path $path\*.psd1; Unblock-File -Path $path\Public\*.ps1`
5. Reopen PowerShell one more time and you can start using the cmdlets

_Note: You are not limited to installing the module to those example paths, you can add a new entry to the environment variable `PSModulePath` if you want to use another path._


## Examples

There is only one cmdlet that is included in this module but it is designed to
be flexible and suite the code you want to invoke. Here are some C# code
examples and how to invoke them

### Simple void method

Import-Module -Name C:\temp\PSCSharpInvoker\PSCSharpInvoker\PSCSharpInvoker.psd1

```
$code = @'
using System;

public class PSCSharpInvoker
{
    public static void Run()
    {
        Console.WriteLine("Running in the domain: {0}", System.AppDomain.CurrentDomain.FriendlyName);
    }
}
'@

Invoke-CSharpMethod -Code $code -Class PSCSharpInvoker -Method Run
```

### Method with return value

```
$code = @'
using System;

namespace CustomNamespace
{
    public class PSCSharpInvoker
    {
        public static void Run()
        {
            Console.WriteLine("Running in the domain: {0}", System.AppDomain.CurrentDomain.FriendlyName);
        }
    }   
}
'@

$return_value = Invoke-CSharpMethod -Code $code -Class CustomNamespace.PSCSharpInvoker -Method Run

Write-Output "Method returned: '$return_value'"
```

### Method with arguments

```
$code = @'
using System;
using System.Collections.Generic;

public class PSCSharpInvoker
{
    public static void SingleArgument(string arg)
    {
        Console.WriteLine(arg);
    }

    public static void SingleArrayArgument(int[] args)
    {
        Console.WriteLine(String.Join(", ", args));
    }

    public static void MultipleArguments(string arg1, bool arg2)
    {
        Console.WriteLine("arg1: '{0}', arg2: '{1}'", arg1, arg2);
    }

    public static void MultipleArgsWithArray(string[] arg1, List<string> arg2)
    {
        Console.WriteLine("'{0}', '{1}'", String.Join(", ", arg1), String.Join(", ", arg2));
    }

    public static void ParamsArgument(params string[] args)
    {
        Console.WriteLine(String.Join(", ", args));
    }

    public static void ParamsWithDefaults(string arg1, string arg2 = "arg2")
    {
        Console.WriteLine("arg1: '{0}', arg2: '{1}'", arg1, arg2);
    }
}
'@

Invoke-CSharpMethod -Code $code -Class PSCSharpInvoker -Method SingleArgument -Arguments "argument 1"

# due to PowerShell parameter handling, we need to ensure the array arg is passed
# in as the first element of the existing array
$argument = [Int[]]@(1, 2, 3)
Invoke-CSharpMethod -Code $code -Class PSCSharpInvoker -Method SingleArrayArgument -Arguments @(,$argument)

Invoke-CSharpMethod -Code $code -Class PSCSharpInvoker -Method MultipleArguments -Arguments "argument 1", $false

$arg1 = [String[]]@("array 1", "array 2")
$arg2 = [System.Collections.Generic.List`1[String]]@("list 1", "list 2")
Invoke-CSharpMethod -Code $code -Class PSCSharpInvoker -Method MultipleArgsWithArray -Arguments $arg1, $arg2

$arguments = [String[]]@("argument 1", "argument 2")
Invoke-CSharpMethod -Code $code -Class PSCSharpInvoker -Method ParamsArgument -Arguments @(,$arguments)

# when wanting to use the default value for a parameter, pass in [Type]::Missing
Invoke-CSharpMethod -Code $code -Class PSCSharpInvoker -Method ParamsWithDefaults -Arguments "arg 1", ([Type]::Missing)

# specifying an actual param at the index to override it
Invoke-CSharpMethod -Code $code -Class PSCSharpInvoker -Method ParamsWithDefaults -Arguments "arg 1", "arg override"
```

### Method with referenced assembly

The below example uses a clas that's in the `System.Web.Extensions` assembly.
To run, you need to specify the assembly location when calling the
`Invoke-CSharpMethod` cmdlet. Usually the location is just the DLL name but
you may need to specify the full path.

```
$code = @'
using System;
using System.Web.Script.Serialization;

public class Json
{
    public static string Serialize(object obj)
    {
        JavaScriptSerializer jss = new JavaScriptSerializer();
        return jss.Serialize(obj);
    }
}
'@

$obj = @{
    name = "a hashtable"
    value = "some value"
}
Invoke-CSharpMethod -Code $code -Class Json -Method Serialize -Arguments $obj -ReferencedAssemblies "System.Web.Extensions.dll"

# produces
{"name":"a hashtable","value":"some value"}
```

If you are unsure of the location to an assembly but the type is already loaded
in PowerShell, you can easily get the path by running;

```
$type = [Type]
([System.Reflection.Assembly]::GetAssembly($type)).Location
```

If you know the name of the assembly when using `Add-Type -AssemblyName`, you
can also get the location by running;

```
(Add-Type -AssemblyName System.Web.Extensions -PassThru)[0].Assembly.Location
```


## Contributing

Contributing is quite easy, fork this repo and submit a pull request with the
changes. To test out your changes locally you can just run `.\build.ps1` in
PowerShell. This script will ensure all dependencies are installed before
running the test suite.

_Note: this requires PowerShellGet or WMF 5 to be installed_
