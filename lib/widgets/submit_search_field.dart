import 'package:flutter/material.dart';

/// Keeps edits in the controller until the user explicitly submits a search.
class SubmitSearchField extends StatelessWidget {
  const SubmitSearchField({
    super.key,
    required this.controller,
    required this.onSearch,
    required this.decoration,
    this.searchLabel = '검색',
  });

  final TextEditingController controller;
  final ValueChanged<String> onSearch;
  final InputDecoration decoration;
  final String searchLabel;

  @override
  Widget build(BuildContext context) {
    void submit() {
      onSearch(controller.text);
      FocusScope.of(context).unfocus();
    }

    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => submit(),
      decoration: decoration.copyWith(
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (decoration.suffixIcon != null) decoration.suffixIcon!,
            TextButton(onPressed: submit, child: Text(searchLabel)),
          ],
        ),
      ),
    );
  }
}
