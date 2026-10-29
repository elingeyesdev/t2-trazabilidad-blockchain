import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AppLoading extends StatelessWidget {
  const AppLoading({super.key, this.message = 'Cargando...'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const SizedBox.expand(
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: AppTheme.forest,
                        backgroundColor: AppTheme.sage,
                      ),
                    ),
                    const Icon(
                      Icons.eco_outlined,
                      color: AppTheme.forest,
                      size: 28,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
