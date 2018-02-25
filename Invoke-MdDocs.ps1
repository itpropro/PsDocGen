<#
.SYNOPSIS
Generates Markdown documentation for PowerShell Script- or Modulefiles.
.DESCRIPTION
Generates Markdown documentation for PowerShell Script- or Modulefiles.
.PARAMETER scriptFile
Specifies the path to the script or module file.
.PARAMETER outputFile
Specifies the path to the markdown output file.
.INPUTS
None. You cannot pipe objects to Update-Month.ps1.
.OUTPUTS
None. Update-Month.ps1 does not generate any output.
.EXAMPLE
C:\PS> Invoke-MdDocs -outputFile 'C:\temp\out.md' -scriptFile 'C:\temp\script.ps1'
#>

param
(
    [parameter(Mandatory = $true)]
    [string]$scriptFile,
    [parameter(Mandatory = $true)]
    [string]$outputFile
)

if (-not (Test-Path $scriptFile))
{
    Write-Error 'Scriptfile not found. Exiting...'
    exit
}

if (-not (get-module -ListAvailable -Name EPS))
{
    Write-Error 'EPS PowerShell module not found, use "Install-Module EPS" and try again.'
    exit
}

# Get the AST of the file

$tokens = $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $scriptFile,
    [ref]$tokens,
    [ref]$errors)

$header = Invoke-Command {

    if ($ast.GetHelpContent())
    {
        $commentBlock = $ast.GetHelpContent().GetCommentBlock()
    }
    else 
    {
        $commentBlock = [System.Management.Automation.Language.CommentHelpInfo]::new()
    }

    $scriptBlock = [scriptblock]::Create(('
    function {0} {{
        {1}
        {2}
    }}' -f (Get-Item $scriptFile).Name, $commentBlock, $ast.ParamBlock.Extent.Text))

    & {
        . $scriptBlock
        Get-Help (Get-Item $scriptFile).Name
    }
}

# Get only function definition ASTs

$functionDefinitions = $ast.FindAll(
{
    param(
        [System.Management.Automation.Language.Ast] $Ast
    )
    $Ast -is [System.Management.Automation.Language.FunctionDefinitionAst] -and ($PSVersionTable.PSVersion.Major -lt 5 -or $Ast.Parent -isnot [System.Management.Automation.Language.FunctionMemberAst])
}, $true)

$helpContent = $functionDefinitions | ForEach-Object {

    if ($_.GetHelpContent())
    {
        $commentBlock = $_.GetHelpContent().GetCommentBlock()
    }
    else 
    {
        $commentBlock = ''
    }
    $scriptBlock = [scriptblock]::Create(('
    function {0} {{
        {1}
        {2}
    }}' -f $_.Name, $commentBlock, $_.Body.ParamBlock.Extent.Text))

    & {
        . $scriptBlock
        
        Get-Help $_.Name
    }
}

# Manually generate syntax from function parameter objects to handle functions without help header

$i = 0
foreach ($function in $helpContent)
{
    $syntax = ''
    foreach ($item in $function.Syntax.SyntaxItem)
    {
        $syntax += $item.name
        foreach ($parameter in ($item.parameter))
        {
            if ($parameter.required -eq 'true')
            {
                $syntax += ' [-{0}]{1}' -f $parameter.name, (. ($({" <$($parameter.parameterValue)>"}), {})[!$parameter.parameterValue])
            }
            else 
            {
                $syntax += ' [[-{0}{1}]' -f $parameter.name, (. ($({" <$($parameter.parameterValue)>"}), {})[!$parameter.parameterValue])
            }
        }
        if (([System.String]::IsNullOrEmpty($function.Syntax.syntaxItem.count)) -or ($function.Syntax.syntaxitem[$function.Syntax.syntaxItem.count - 1] -eq $item))
        {
            $syntax += " [<CommonParameters>]"
        }
        else
        {
            $syntax += " [<CommonParameters>]`n"
        }
    }
    $helpContent[$i].Syntax = $syntax
    $i++
}

Invoke-EpsTemplate -Path .\md.eps -Safe -Binding @{header = $header; helpContent = $helpContent} | Out-File $outputFile