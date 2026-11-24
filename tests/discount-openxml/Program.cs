using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Validation;

var failed = false;
foreach (var path in args) {
  using var book = SpreadsheetDocument.Open(path, false);
  var errors = new OpenXmlValidator(FileFormatVersions.Office2019).Validate(book).ToList();
  foreach (var error in errors.Take(30))
    Console.WriteLine($"{path}: {error.Part?.Uri} {error.Path?.XPath}: {error.Description}");
  Console.WriteLine($"{path}: Open XML validation errors = {errors.Count}");
  failed |= errors.Count != 0;
}
return failed ? 1 : 0;
