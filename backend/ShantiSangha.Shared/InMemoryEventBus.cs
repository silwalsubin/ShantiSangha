using System.Collections.Concurrent;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Shared;

public class InMemoryEventBus : IEventBus
{
    private readonly ConcurrentDictionary<Type, List<Func<object, CancellationToken, Task>>> _handlers = new();

    public async Task PublishAsync<TEvent>(TEvent @event, CancellationToken ct = default) where TEvent : class
    {
        if (_handlers.TryGetValue(typeof(TEvent), out var handlers))
        {
            foreach (var handler in handlers)
                await handler(@event, ct);
        }
    }

    public void Subscribe<TEvent>(Func<TEvent, CancellationToken, Task> handler) where TEvent : class
    {
        var wrapper = new Func<object, CancellationToken, Task>((obj, ct) => handler((TEvent)obj, ct));
        _handlers.GetOrAdd(typeof(TEvent), _ => []).Add(wrapper);
    }
}
