import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';

import '../../api_agent.dart';
import 'imports_builder.dart';

const annotationChecker = TypeChecker.typeNamed(ApiDefinition);

String? getMetaProperty(Element element, String propertyName,
    [ImportsBuilder? imports]) {
  for (ElementAnnotation annotation in element.metadata.annotations) {
    final DartObject? annotationValue = annotation.computeConstantValue();
    if (annotationValue == null) continue;

    // Try to get the property from the annotation
    final DartObject? propertyValue = annotationValue.getField(propertyName);
    if (propertyValue == null) continue;

    // Try different ways to extract a string value

    // Direct string value
    final String? directString = propertyValue.toStringValue();
    if (directString != null) return directString;

    // If it's a reference to a const variable or class name
    final Element? propertyElement = propertyValue.type?.element;
    if (propertyElement != null) {
      return propertyElement.name;
    }

    // If it's an enum, get its string representation
    if (propertyValue.type?.element is EnumElement) {
      // For enum, you might want the enum value name
      final enumName = propertyValue.getField('_name')?.toStringValue();
      if (enumName != null) return enumName;
    }

    // If it's a Type reference (e.g., MyClass as a type literal)
    final typeValue = propertyValue.toTypeValue();
    if (typeValue != null) {
      return typeValue.getDisplayString(withNullability: false);
    }
  }

  return null;
}

extension GetNode on Element {
  AstNode? getNode() {
    var result = session?.getParsedLibraryByElement(library!);
    if (result is ParsedLibraryResult) {
      return null; // TODO: Fix getNode extension for analyzer 8.0
    } else {
      return null;
    }
  }
}

extension MethodImports on MethodElement {
  List<Uri> getImports() {
    return [
      ...returnType.getImports(),
      ...formalParameters.expand((p) => p.type.getImports())
    ];
  }
}

extension TypeImports on DartType {
  List<Uri> getImports() {
    if (this is InterfaceType) return (this as InterfaceType).getImports();
    if (element?.library?.isInSdk ?? false) return [];
    var uri = element?.library?.uri;
    return uri != null ? [uri] : [];
  }
}

extension InterfaceTypeImports on InterfaceType {
  List<Uri> getImports() {
    return [
      if (!element.library.isInSdk) element.library.uri,
      ...typeArguments.expand((t) => t.getImports()),
    ];
  }
}
