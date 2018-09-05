# Copyright: (c) 2018, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)

Function Invoke-CSharpMethod {
    <#
    .SYNOPSIS
    Run a C# static method without loading the type in the current AppDomain or
    starting a new process. This ensures the type is not persisted in the
    PowerShell AppDomain allowing a user to modify the C# code without creating
    a new process.

    .DESCRIPTION
    Will invoke the C# method defined by the user in a separate AppDomain and
    will output the return value back to the user. Because the code is run in
    a separate AppDomain, the types are not loaded in the current PowerShell
    AppDomain meaning a different piece of code using the same types can be
    run without creating a new process.

    .PARAMETER Code
    [String] The C# code to compile and run

    .PARAMETER Class
    [String] The full name of the class that Method is located in

    .PARAMETER Method
    [String] The static method to invoke on the class

    .PARAMETER ReferencedAssemblies
    [System.Collections.Generic.HashSet`1[String]] A list of assembly locations
    for assemblies that are referenced in the code. By default this will
    include System.dll and System.Management.Automation.dll.

    .PARAMETER Arguments
    [Object] Any arguments (if any) to pass in as the method params. This can
    be difficult when passing in arrays due to how PowerShell handles them. The
    safest way would be to define the value for Arguments as @(,$arg1) where
    $arg1 may be any value (including an array).

    Use [Type]::Missing when dealing with parameters with default values and
    you want to use the default parameter.

    A params parameter (params string[] args) is treated as a singular
    argument, set the argument in this position as an array of the defined
    type.

    .PARAMETER IgnoreWarnings
    [Switch] Whether to ignore any compiler warnings when compiling the code

    .OUTPUTS
    This cmdlet will return whatever is returned from the C# method.

    .EXAMPLE
    $code = @'
    using System;
    using System.Web.Script.Serialization;

    namespace PSCSharpInvoker
    {
        public class Example
        {
            public static string Run(string[] args)
            {
                string currentDomain = System.AppDomain.CurrentDomain.FriendlyName;
                Console.WriteLine("Invoked in {0}. Arguments: '{1}'", currentDomain, String.Join(", ", args));
                return "finished";
            }
        }
    }
    '@

    $arguments = [String[]]@("arg 1", "arg 2")
    Invoke-CSharpMethod -Code $code -Class PSCSharpInvoker.Example -Method Run `
        -ReferencedAssemblies "System.Web.Extensions.dll" -Arguments @(,$arguments)

    .NOTES
    This is mostly a proof of concept to prove that it is possible to invoke C#
    code and ensure the types are not persisted in the current PowerShell
    session. Due to the AppDomain boundary there are restrictions on the types
    that can be used are arguments as well as the types that can be returned
    from the C# method. Supported types are the ones that have the
    SerializableAttribute set
    https://docs.microsoft.com/en-us/dotnet/api/system.serializableattribute?view=netframework-4.7.2.
    #>
    param(
        [Parameter(Mandatory=$true)][String]$Code,
        [Parameter(Mandatory=$true)][String]$Class,
        [Parameter(Mandatory=$true)][String]$Method,
        [AllowEmptyCollection()][System.Collections.Generic.HashSet`1[String]]$ReferencedAssemblies = @(),
        [Parameter(ValueFromRemainingArguments=$true)][Object]$Arguments,
        [Switch]$IgnoreWarnings
    )
    # defines the C# code that is used to run our C# code in the separate
    # AppDomain. It contains the ResolveEventHandler we use to resolve this
    # assembly even when not persisting it to the disk as well as the Runner
    # class that runs the C# code in the separate AppDomain.
    $exec_wrapper = @'
using Microsoft.CSharp;
using System;
using System.CodeDom.Compiler;
using System.Collections;
using System.Collections.Generic;
using System.Reflection;

namespace ExecWrapper
{
    public class Redirector
    {
        public readonly ResolveEventHandler EventHandler;
        private Assembly overrideAssembly;
        private string overrideTypeName;

        public Redirector(Type customType, string assemblyName)
        {
            EventHandler = new ResolveEventHandler(AssemblyResolve);
            overrideAssembly = customType.Assembly;
            overrideTypeName = assemblyName;
        }

        protected Assembly AssemblyResolve(object sender, ResolveEventArgs resolveEventArgs)
        {
            // return our own Assembly if the name matches the DLL filename
            if (resolveEventArgs.Name.StartsWith(overrideTypeName))
                return overrideAssembly;

            // otherwise try and load the assemblies in the current domain
            foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies())
                if (resolveEventArgs.Name == assembly.FullName)
                    return assembly;

            return null;
        }
    }

    public class Runner : MarshalByRefObject
    {
        public object Run(string code, string[] referencedAssemblies, bool ignoreWarnings, string type, string method, object[] args)
        {
            Assembly compiledAssembly = Compile(code, referencedAssemblies, ignoreWarnings);
            Type codeType = GetAssemblyType(compiledAssembly, type);

            BindingFlags bindingFlags = BindingFlags.InvokeMethod | BindingFlags.Public | BindingFlags.Static;
            MethodInfo entryMethod = codeType.GetMethod(method, bindingFlags);
            if (entryMethod == null)
                throw new InvalidOperationException(String.Format("Failed to find the method {0} in the type {1}", method, type));

            try
            {
                return entryMethod.Invoke(null, args);
            }
            catch (TargetParameterCountException e)
            {
                List<string> methodParameters = new List<string>();
                foreach (ParameterInfo pi in entryMethod.GetParameters())
                    methodParameters.Add(String.Format("{0} {1}", pi.ParameterType.Name, pi.Name));

                List<string> actualParameters = new List<string>();
                if (args != null)
                    foreach (object arg in args)
                        actualParameters.Add(arg.GetType().Name);

                string msg = String.Format("{0}\r\nMethod parameters {1}: {2}\r\nActual parameters {3}: {4}",
                    e.Message, methodParameters.Count, String.Join(", ", methodParameters),
                    actualParameters.Count, String.Join(", ", actualParameters));
                throw new TargetParameterCountException(msg);
            }
        }

        private Assembly Compile(string code, string[] referencedAssemblies, bool ignoreWarnings)
        {
            // Compiles the module code and returns the loaded type that
            // contains the Main method
            CompilerParameters compilerParams = new CompilerParameters()
            {
                CompilerOptions = "/optimize",
                GenerateExecutable = false,
                GenerateInMemory = true,
                TreatWarningsAsErrors = !ignoreWarnings
            };
            compilerParams.ReferencedAssemblies.AddRange(referencedAssemblies);

            CSharpCodeProvider provider = new CSharpCodeProvider();
            CompilerResults compile = provider.CompileAssemblyFromSource(compilerParams, code);
            if (compile.Errors.HasErrors)
            {
                string msg = "Compile error: ";
                foreach (CompilerError e in compile.Errors)
                    msg += "\r\n" + e.ToString();
                throw new InvalidOperationException(msg);
            }

            return compile.CompiledAssembly;
        }

        private Type GetAssemblyType(Assembly assembly, string type)
        {
            List<string> loadedTypes = new List<string>();
            Type actualType = null;
            foreach (Type assemblyType in assembly.GetTypes())
            {
                loadedTypes.Add(assemblyType.FullName);
                if (assemblyType.FullName == type)
                {
                    actualType = assemblyType;
                    break;
                }
            }

            if (actualType == null)
            {
                string msg = String.Format("failed to find the type {0} in the loaded assembly, found types: {1}",
                    type, String.Join(", ", loadedTypes));
                throw new InvalidOperationException(msg);
            }
            return actualType;
        }
    }
}
'@

    # add the System and System.Management.Automation assemblies to mimic the
    # behaviour of Add-Type -ReferencedAssemblies
    $ReferencedAssemblies.Add("System.Core.dll") > $null
    $ReferencedAssemblies.Add(([System.Reflection.Assembly]::GetAssembly([PSObject])).Location) > $null
    $ref_assemblies = New-Object -TypeName string[] -ArgumentList $ReferencedAssemblies.Count
    $ReferencedAssemblies.CopyTo($ref_assemblies)

    # create a temporary DLL that contains the compiled exec wrapper code. We
    # need touch the disk temporarily so that both the current and new
    # AppDomain can load the types
    $exec_dll = [System.IO.Path]::GetTempFileName()
    Add-Type -TypeDefinition $exec_wrapper -OutputAssembly $exec_dll

    # load the exec_wrapper based on the output DLL made above, cannot use
    # LoadFrom as that will lock the DLL until the current process ends
    # stopping the code from deleting the file once it's no longer needed.
    # Because we don't use LoadFrom the assembly has a random name and is the
    # reason why we have a custom ResolveEventHandler to load this random
    # assembly name if it's been asked to load it based on the dll filename
    $exec_types = ([System.Reflection.Assembly]::Load([System.IO.File]::ReadAllBytes($exec_dll))).GetTypes()
    $redirector_type = $exec_types | Where-Object { $_.Name -eq "Redirector" }
    $runner_type = $exec_types | Where-Object { $_.Name -eq "Runner" }

    # create an handler to point to our in memory loaded assembly when it tries
    # to load the the assembly based on the filename. This allows us to load
    # the types in the current AppDomain in memory but still reference the in
    # memory assembly based on a file assembly name
    $runner_assembly_name = [System.IO.Path]::GetFileNameWithoutExtension($exec_dll)
    $redirector = New-Object -TypeName $redirector_type -ArgumentList $runner_type, $runner_assembly_name

    # create a new AppDomain with ShadowCopyFiles set to true, this means that the
    # new AppDomain will not lock our local DLL file when loading it allowing us to
    # delete it once it's loaded
    $domain_setup = New-Object -TypeName System.AppDomainSetup
    $domain_setup.ShadowCopyFiles = "true"  # this is meant to be a string
    $domain_guid = [System.Guid]::NewGuid()
    $domain = [System.AppDomain]::CreateDomain("TempDomain-$domain_guid", $null, $domain_setup)

    try {
        # add the custom assembly redirector handler before loading the exec
        # DLL in the new AppDomain. This must be done as the data is
        # serialised between domains and the current domain needs to know how
        # to map the assemblies to the ones in the current domain
        [System.AppDomain]::CurrentDomain.add_AssemblyResolve($redirector.EventHandler)

        try {
            # load the exec wrapper in the new AppDomain and create an instance
            # of the Runner class for us to invoke from the current AppDomain
            $exec_runner = $domain.CreateInstanceFromAndUnwrap($exec_dll, $runner_type.FullName)

            # once the new AppDomain has loaded our DLL we can delete the local
            # copy of it as it's no longer needed
            [System.IO.File]::Delete($exec_dll)

            # call the Run method on the Runner class that runs in the other AppDomain.
            $exec_runner.Run($code, $ref_assemblies, $IgnoreWarnings.IsPresent, $Class, $Method, $Arguments)
        } finally {
            [System.AppDomain]::CurrentDomain.remove_AssemblyResolve($redirector.EventHandler)
        }
    } finally {
        [System.AppDomain]::Unload($domain)
    }
}